#pragma once
// rpicam-vid 를 자식 프로세스로 띄워 YUV420 을 파이프로 받는다. 최신 프레임 하나만 남긴다.
#include <atomic>
#include <chrono>
#include <cerrno>
#include <csignal>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <sys/wait.h>
#include <unistd.h>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

class RpicamSource {
public:
    // extra: rpicam-vid 에 그대로 붙일 인자
    RpicamSource(int width, int height, int fps, const std::vector<std::string>& extra) : w(width), h(height) {
        std::vector<std::string> args = {"rpicam-vid", "-n", "-t", "0", "--codec", "yuv420",
                                         "--width", std::to_string(w), "--height", std::to_string(h),
                                         "--framerate", std::to_string(fps), "-o", "-"};
        args.insert(args.end(), extra.begin(), extra.end());
        int fd[2];
        if (pipe(fd) != 0) { alive = false; return; }
        pid = fork();
        if (pid == 0) {
            dup2(fd[1], STDOUT_FILENO);
            close(fd[0]);
            close(fd[1]);
            std::vector<char*> argv;
            for (auto& a : args) argv.push_back(a.data());
            argv.push_back(nullptr);
            execvp(argv[0], argv.data());
            _exit(127);
        }
        close(fd[1]);
        in = fd[0];
        reader = std::thread([this] { loop(); });
    }

    ~RpicamSource() {
        if (pid > 0) kill(pid, SIGTERM);
        if (reader.joinable()) reader.join();
        if (in >= 0) close(in);
        if (pid > 0) waitpid(pid, nullptr, 0);
    }

    bool running() const { return alive; }

    // seq 는 이 프로세스 안의 프레임 번호, at 은 받은 시각 (촬영 시각으로 쓴다)
    bool next(cv::Mat& bgr, uint64_t& seq, int timeoutMs = 2000, std::chrono::steady_clock::time_point* at = nullptr) {
        std::unique_lock<std::mutex> lk(m);
        if (!ready.wait_for(lk, std::chrono::milliseconds(timeoutMs), [&] { return latestSeq != taken || !alive; }))
            return false;
        if (latestSeq == taken) return false;
        taken = seq = latestSeq;
        if (at) *at = latestAt;
        cv::Mat yuv = latest;
        lk.unlock();
        cv::cvtColor(yuv, bgr, cv::COLOR_YUV2BGR_I420);
        return true;
    }

private:
    // 줄 끝 여백이 없다고 가정하므로 폭은 128 배수여야 한다
    void loop() {
        const size_t size = (size_t)w * h * 3 / 2;
        std::vector<unsigned char> buf(size);
        while (true) {
            size_t got = 0;
            while (got < size) {
                ssize_t r = read(in, buf.data() + got, size - got);
                if (r < 0 && errno == EINTR) continue;
                if (r <= 0) break;
                got += r;
            }
            if (got < size) break;
            {
                std::lock_guard<std::mutex> lk(m);
                latest = cv::Mat(h * 3 / 2, w, CV_8U, buf.data()).clone();
                latestAt = std::chrono::steady_clock::now();
                ++latestSeq;
            }
            ready.notify_all();
        }
        {
            std::lock_guard<std::mutex> lk(m);
            alive = false;
        }
        ready.notify_all();
    }

    int w, h;
    pid_t pid = -1;
    int in = -1;
    std::thread reader;
    std::mutex m;
    std::condition_variable ready;
    cv::Mat latest;
    uint64_t latestSeq = 0, taken = 0;
    std::chrono::steady_clock::time_point latestAt;
    std::atomic<bool> alive{true};
};
