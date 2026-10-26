#pragma once
// ATLAS camera client: Open -> SetFormat -> Start -> GetFd -> shared memory read.
// SetFormat 에 fps 를 빠뜨리면 Start 가 실패한다.
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <string>
#include <stdexcept>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <camera/camera_client.h>
#include <camera/camera_shared_memory.h>

class Camera {
public:
    explicit Camera(const std::string& want = "", int w = 640, int h = 480, int fps = 30) : W(w), H(h) {
        auto& c = camera::CameraClient::instance();
        if (c.Open(choose(want), handle) != 0) throw std::runtime_error("Open");
        camera::frame_info_t f{w, h, fps, camera::CAMERA_FORMAT_YUV};
        if (c.SetFormat(handle, f) != 0) { c.Close(handle); throw std::runtime_error("SetFormat"); }
        if (c.Start(handle) != 0) { c.Close(handle); throw std::runtime_error("Start"); }
        int fd0 = -1, fd1 = -1;                       // 0 = 버퍼, 1 = 프레임 신호
        if (c.GetFd(handle, 0, fd0) != 0 || c.GetFd(handle, 1, fd1) != 0 || !shm.open(fd0, fd1)) {
            c.Stop(handle); c.Close(handle); throw std::runtime_error("공유버퍼");
        }
        yuyv.create(H, W, CV_8UC2);
    }
    ~Camera() {
        auto& c = camera::CameraClient::instance();
        shm.close(); c.Stop(handle); c.Close(handle);
    }
    // 명령을 계속 받을 수 있게 200ms 만 기다린다. 시간 초과면 빈 Mat
    cv::Mat read() {
        unsigned char *data, *meta, *extra; size_t ds, ms, es;
        if (!shm.read(&data, &ds, &meta, &ms, &extra, &es, 200)) return {};
        memcpy(yuyv.data, data, std::min(ds, (size_t)W * H * 2));
        cv::Mat bgr; cv::cvtColor(yuyv, bgr, cv::COLOR_YUV2BGR_YUYV);
        return bgr;
    }
private:
    // 모델 이름에 want 가 들어 있는 카메라, 없으면 첫 번째
    static std::string choose(const std::string& want) {
        auto& c = camera::CameraClient::instance();
        auto devs = c.DeviceList();
        if (devs.empty()) throw std::runtime_error("카메라 없음");

        std::string wanted = lower(want);
        for (const auto& id : devs) {
            camera::device_info_t info;
            std::string label = c.GetDeviceInfo(id, info) == 0 ? id + " (" + info.modelName + ")" : id;
            bool match = !wanted.empty() && lower(label).find(wanted) != std::string::npos;
            std::fprintf(stderr, "[vision] 카메라 %s%s\n", label.c_str(), match ? " <- 고름" : "");
            if (match) return id;
        }
        return devs[0];
    }

    static std::string lower(std::string text) {
        std::transform(text.begin(), text.end(), text.begin(), [](unsigned char ch) { return std::tolower(ch); });
        return text;
    }

    int32_t handle = -1;
    int W, H;
    CameraSharedMemory shm;
    cv::Mat yuyv;
};
