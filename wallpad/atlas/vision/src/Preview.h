#pragma once
// 미리보기 파일: BGRA 320x240, 좌우 반전.
#include <cstdio>
#include <fstream>
#include <string>
#include <opencv2/imgproc.hpp>

class Preview {
public:
    static constexpr int WIDTH = 320, HEIGHT = 240;

    explicit Preview(std::string path) : file(std::move(path)) {}

    const std::string& path() const { return file; }

    // 앱이 쓰다 만 파일을 읽지 않도록 임시 파일에 쓰고 rename
    void write(const cv::Mat& img) const {
        cv::Mat small, bgra;
        cv::resize(img, small, {WIDTH, HEIGHT});
        cv::flip(small, small, 1);
        cv::cvtColor(small, bgra, cv::COLOR_BGR2BGRA);
        std::string tmp = file + ".tmp";
        {
            std::ofstream out(tmp, std::ios::binary);
            out.write((const char*)bgra.data, bgra.total() * 4);
        }
        std::rename(tmp.c_str(), file.c_str());
    }

    void clear() const { std::remove(file.c_str()); }

private:
    std::string file;
};
