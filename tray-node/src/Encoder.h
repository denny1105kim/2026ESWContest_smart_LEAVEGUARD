#pragma once
// 크롭 -> 특징 벡터 (OpenCV dnn, ONNX). DINOv2 ONNX 는 배치 1 로 굳어 있어 한 장씩 돌린다.
#include <algorithm>
#include <cmath>
#include <fstream>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>
#include <opencv2/core.hpp>
#include <opencv2/dnn.hpp>
#include <opencv2/imgproc.hpp>
#include "Sha256.h"

struct EncoderSpec {
    std::string name;
    int input = 0;         // 정사각 입력 한 변
    int dim = 0;
    std::string output;    // cls | gap
    bool l2 = false;
};

inline bool encoderPreset(const std::string& preset, EncoderSpec& s) {
    if (preset == "orbit_protonets_effb0_224") { s = {preset, 224, 1280, "gap", false}; return true; }
    if (preset == "dinov2_vits14_reg_168") { s = {preset, 168, 384, "cls", true}; return true; }
    return false;
}

class Encoder {
public:
    // 자동 후보는 물건에 딱 붙어서, 사람이 그린 박스와 여백을 맞추려고 넓힌다
    static constexpr float PAD = 0.12f;

    Encoder(const EncoderSpec& spec, const std::string& modelPath) : s(spec) {
        net = cv::dnn::readNetFromONNX(modelPath);
        std::ifstream f(modelPath, std::ios::binary);
        std::vector<unsigned char> bytes((std::istreambuf_iterator<char>(f)), {});
        hash = Sha256::hex(bytes).substr(0, 16);
        // preset 과 모델 파일이 맞는지 확인
        cv::Mat probe = run(cv::Mat(s.input, s.input, CV_8UC3, cv::Scalar(128, 128, 128)));
        if (probe.empty()) throw std::runtime_error("모델 출력이 스펙(" + s.name + ", " + std::to_string(s.dim) + "차원)과 맞지 않음: " + modelPath);
    }

    // 두 벡터를 각각 L2 정규화해 이어 붙이고 다시 L2 (같은 무게)
    void addSecond(const EncoderSpec& spec2, const std::string& path2) { second = std::make_unique<Encoder>(spec2, path2); }

    const EncoderSpec& spec() const { return s; }
    int dim() const { return s.dim + (second ? second->s.dim : 0); }
    bool l2() const { return second ? true : s.l2; }

    // Pi5 는 ID 가 다른 벡터끼리 비교하지 않는다. 전처리를 바꾸면 이 문자열도 바꾼다
    std::string spaceId() const {
        if (second)
            return s.name + "@" + hash + "+" + second->s.name + "@" + second->hash + "/rgb-sq0-imagenet/pad" +
                   std::to_string((int)std::lround(PAD * 100)) + "/concat-l2/f32";
        return s.name + "@" + hash + "/rgb-sq0-resize" + std::to_string(s.input) + "-imagenet/pad" +
               std::to_string((int)std::lround(PAD * 100)) + "/" + s.output + (s.l2 ? "-l2" : "") + "/f32";
    }

    static cv::Rect padded(const cv::Rect& box, const cv::Size& size) {
        int dx = cvRound(box.width * PAD), dy = cvRound(box.height * PAD);
        return cv::Rect(box.x - dx, box.y - dy, box.width + 2 * dx, box.height + 2 * dy) & cv::Rect({}, size);
    }

    // box 는 원본 좌표, 여백 전. 실패하면 빈 Mat
    cv::Mat encode(const cv::Mat& bgr, const cv::Rect& box) {
        cv::Rect r = padded(box, bgr.size());
        if (r.width < 8 || r.height < 8) return {};
        return fuse(bgr(r));
    }

    cv::Mat encodeRotated(const cv::Mat& bgr, const cv::Rect& box, int rot) {
        cv::Rect r = padded(box, bgr.size());
        if (r.width < 8 || r.height < 8) return {};
        cv::Mat turned;
        cv::rotate(bgr(r), turned, rot == 90 ? cv::ROTATE_90_CLOCKWISE : rot == 180 ? cv::ROTATE_180 : cv::ROTATE_90_COUNTERCLOCKWISE);
        return fuse(turned);
    }

    cv::Mat encodeCrop(const cv::Mat& crop) { return fuse(crop); }

private:
    cv::Mat fuse(const cv::Mat& crop) {
        cv::Mat a = run(crop);
        if (!second || a.empty()) return a;
        cv::Mat b = second->run(crop);
        if (b.empty()) return {};
        cv::Mat out;
        cv::hconcat(std::vector<cv::Mat>{cv::Mat(a / cv::norm(a)), cv::Mat(b / cv::norm(b))}, out);
        return out / std::sqrt(2.0);
    }

    // 늘리지 않고 검은색(판 색)으로 채워 정사각형으로. crop 이 ROI 라서 BORDER_ISOLATED 가 필요하다
    static cv::Mat square(const cv::Mat& crop) {
        int side = std::max(crop.cols, crop.rows), top = (side - crop.rows) / 2, left = (side - crop.cols) / 2;
        if (crop.cols == crop.rows) return crop;
        cv::Mat out;
        cv::copyMakeBorder(crop, out, top, side - crop.rows - top, left, side - crop.cols - left, cv::BORDER_CONSTANT | cv::BORDER_ISOLATED, cv::Scalar(0, 0, 0));
        return out;
    }

    cv::Mat run(const cv::Mat& crop) {
        std::lock_guard<std::mutex> lock(busy);
        cv::Mat blob = cv::dnn::blobFromImage(square(crop), 1 / 255.0, {s.input, s.input}, {}, /*swapRB=*/true, /*crop=*/false);
        static constexpr float mean[] = {0.485f, 0.456f, 0.406f}, stdev[] = {0.229f, 0.224f, 0.225f};
        for (int c = 0; c < 3; ++c) {
            cv::Mat channel(s.input, s.input, CV_32F, blob.ptr<float>(0, c));
            channel -= mean[c];
            channel /= stdev[c];
        }
        net.setInput(blob);
        cv::Mat v = net.forward().reshape(1, 1).clone();
        if (v.cols != s.dim || !cv::checkRange(v)) return {};
        double n = cv::norm(v);
        if (n < 1e-6) return {};
        return s.l2 ? cv::Mat(v / n) : v;
    }

    EncoderSpec s;
    cv::dnn::Net net;
    std::string hash;
    std::mutex busy;
    std::unique_ptr<Encoder> second;
};
