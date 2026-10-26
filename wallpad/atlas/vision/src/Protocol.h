#pragma once
// Line protocol with the app: "<name> <session> [args]" in, "<session> <reply>" out.
#include <poll.h>
#include <unistd.h>
#include <cstdio>
#include <sstream>
#include <string>
#include <vector>
#include <opencv2/core.hpp>

struct Command {
    std::string name;
    int session = 0;
    cv::Rect2f guide{0, 0, 1, 1};   // 정규화 좌표 (0~1)
    std::string arg;                // preview/scan: 카메라 이름 일부, door: 0|1, jpeg: 파일 경로
};

// stdin 이 닫히면 false
inline bool readCommands(std::vector<Command>& out, int timeoutMs) {
    static std::string buffer;
    pollfd in{STDIN_FILENO, POLLIN, 0};
    if (poll(&in, 1, timeoutMs) > 0) {
        char chunk[256];
        ssize_t n = read(STDIN_FILENO, chunk, sizeof chunk);
        if (n <= 0) return false;
        buffer.append(chunk, n);
    }
    for (size_t nl; (nl = buffer.find('\n')) != std::string::npos; buffer.erase(0, nl + 1)) {
        Command c;
        std::istringstream line(buffer.substr(0, nl));
        line >> c.name >> c.session;
        std::vector<std::string> rest;
        for (std::string token; line >> token;) rest.push_back(token);
        if (rest.size() == 4) {     // 미리보기가 좌우 반전이라 x 를 되돌린다
            float l = std::stof(rest[0]), t = std::stof(rest[1]), r = std::stof(rest[2]), b = std::stof(rest[3]);
            c.guide = cv::Rect2f(1 - r, t, r - l, b - t);
        } else if (rest.size() == 1) {
            c.arg = rest[0];
        }
        out.push_back(c);
    }
    return true;
}

inline void say(int session, const std::string& what) {
    std::printf("%d %s\n", session, what.c_str());
    std::fflush(stdout);
}

inline std::string numbers(const cv::Mat& row) {
    std::ostringstream out;
    for (int i = 0; i < (int)row.total(); ++i) out << (i ? "," : "") << row.at<float>(0, i);
    return out.str();
}
