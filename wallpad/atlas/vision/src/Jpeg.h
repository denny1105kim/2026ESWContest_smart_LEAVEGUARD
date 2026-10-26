#pragma once
// 보드에 imgcodecs·libjpeg 가 없어 stb_image 로 JPEG 를 푼다.
#include <string>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO_WRITE
#include "stb_image.h"

inline cv::Mat readJpeg(const std::string& path) {
    int w = 0, h = 0, n = 0;
    unsigned char* rgb = stbi_load(path.c_str(), &w, &h, &n, 3);
    if (!rgb) return {};
    cv::Mat bgr;
    cv::cvtColor(cv::Mat(h, w, CV_8UC3, rgb), bgr, cv::COLOR_RGB2BGR);
    stbi_image_free(rgb);
    return bgr;
}
