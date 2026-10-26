// tray-detection-offline: 저장된 사진으로 박스 찾기·특징 추출을 돌린다 (카메라·통신 없음).
//
//   사진: tray-detection-offline --encoder P --model M [--roi x,y,w,h] [--out DIR] [--param k=v]...
//                                [--detector D.onnx [--det-score S] [--det-input N]] 사진...
//         사진마다 관측 JSON 한 줄 (stdout) + DIR/<이름>_mask.png, _boxes.jpg, _cand<i>.png
//   크롭: tray-detection-offline --encoder P --model M --crops 크롭...
//         크롭마다 {"file","embedding_space_id","embedding"} 한 줄
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>
#include <filesystem>
#include <opencv2/imgcodecs.hpp>
#include "Encoder.h"
#include "ItemDetector.h"
#include "Observation.h"
#include "PanelExtractor.h"

using Clock = std::chrono::steady_clock;

static std::string stem(const std::string& path) {
    auto slash = path.find_last_of('/');
    std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
    auto dot = name.find_last_of('.');
    return dot == std::string::npos ? name : name.substr(0, dot);
}

int main(int argc, char** argv) {
    std::string model, preset = "orbit_protonets_effb0_224", out = "tray_detection_out", roiText;
    bool cropsMode = false;
    PanelParams params;
    DetectorParams detParams;
    std::vector<std::string> files;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--model" && i + 1 < argc) model = argv[++i];
        else if (a == "--encoder" && i + 1 < argc) preset = argv[++i];
        else if (a == "--out" && i + 1 < argc) out = argv[++i];
        else if (a == "--roi" && i + 1 < argc) roiText = argv[++i];
        else if (a == "--crops") cropsMode = true;
        else if (a == "--detector" && i + 1 < argc) detParams.model = argv[++i];
        else if (a == "--det-score" && i + 1 < argc) detParams.score = std::stof(argv[++i]);
        else if (a == "--det-input" && i + 1 < argc) detParams.input = std::stoi(argv[++i]);
        else if (a == "--param" && i + 1 < argc) {
            if (!setPanelParam(params, argv[++i])) { std::fprintf(stderr, "모르는 값: %s\n", argv[i]); return 2; }
        } else files.push_back(a);
    }
    if (model.empty() || files.empty()) {
        std::fprintf(stderr, "사용법: %s [--encoder 이름] --model M.onnx [--roi x,y,w,h] [--out DIR] [--param k=v]... [--detector D.onnx] [--det-score S] [--det-input 512] [--crops] 사진...\n", argv[0]);
        return 2;
    }
    if (!roiText.empty()) {
        int x, y, w, h;
        if (std::sscanf(roiText.c_str(), "%d,%d,%d,%d", &x, &y, &w, &h) != 4) { std::fprintf(stderr, "--roi x,y,w,h\n"); return 2; }
        params.roi = {x, y, w, h};
    }

    EncoderSpec spec;
    if (!encoderPreset(preset, spec)) { std::fprintf(stderr, "모르는 --encoder: %s\n", preset.c_str()); return 2; }
    Encoder encoder(spec, model);
    const std::string space = encoder.spaceId();
    std::fprintf(stderr, "[offline] 특징 공간 %s\n", space.c_str());

    if (cropsMode) {
        for (const auto& f : files) {
            cv::Mat crop = cv::imread(f, cv::IMREAD_COLOR);
            if (crop.empty()) { std::fprintf(stderr, "[offline] 못 읽음 %s\n", f.c_str()); continue; }
            cv::Mat v = encoder.encodeCrop(crop);
            std::cout << "{\"file\":" << obs::quote(f) << ",\"embedding_space_id\":" << obs::quote(space)
                      << ",\"embedding\":" << (v.empty() ? "null" : obs::quote(obs::vector64(v))) << "}\n";
        }
        return 0;
    }

    std::filesystem::create_directories(out);
    PanelExtractor extractor(params);
    ItemDetector detector(detParams);
    uint64_t seq = 0;
    for (const auto& f : files) {
        cv::Mat img = cv::imread(f, cv::IMREAD_COLOR);
        if (img.empty()) { std::fprintf(stderr, "[offline] 못 읽음 %s\n", f.c_str()); continue; }
        auto t0 = Clock::now();
        SceneQuality q;
        cv::Mat mask;
        auto cands = extractor.find(img, q, &mask);
        if (detector.enabled()) cands = detect::merge(std::move(cands), q, detector.detect(img, params.roi));
        auto t1 = Clock::now();
        std::vector<cv::Mat> vecs;
        for (const auto& c : cands) vecs.push_back(encoder.encode(img, c.box));
        auto t2 = Clock::now();

        obs::Header h;
        h.deviceId = "offline";
        h.bootId = "offline";
        h.sequence = ++seq;
        h.capturedAt = f;   // 시각 대신 파일 이름
        h.imageWidth = img.cols;
        h.imageHeight = img.rows;
        h.roiVersion = roiText.empty() ? "full" : roiText;
        h.spaceId = space;
        h.frameId = seq;
        h.dim = encoder.dim();
        h.l2 = encoder.l2();
        h.processingMs = std::chrono::duration_cast<std::chrono::milliseconds>(t2 - t0).count();
        std::cout << obs::json(h, q, cands, vecs) << "\n";

        std::string base = out + "/" + stem(f);
        if (!mask.empty()) cv::imwrite(base + "_mask.png", mask);
        cv::Mat vis = img.clone();
        cv::Rect roi = params.roi.area() > 0 ? params.roi : cv::Rect({}, img.size());
        cv::rectangle(vis, roi, {255, 200, 0}, 2);
        for (size_t i = 0; i < cands.size(); ++i) {
            cv::Scalar color = cands[i].source == "panel" ? cv::Scalar(0, 0, 255) : cands[i].source == "split" ? cv::Scalar(255, 0, 255) : cv::Scalar(0, 200, 255);
            cv::rectangle(vis, cands[i].box, color, 3);
            cv::putText(vis, std::to_string(i), cands[i].box.tl() + cv::Point(4, 28), cv::FONT_HERSHEY_SIMPLEX, 1.0, color, 2);
            cv::Rect crop = Encoder::padded(cands[i].box, img.size());
            if (crop.area() > 0) cv::imwrite(base + "_cand" + std::to_string(i) + ".png", img(crop));
        }
        cv::putText(vis, q.valid ? "valid" : ("invalid: " + q.reason), {12, 36}, cv::FONT_HERSHEY_SIMPLEX, 1.0,
                    q.valid ? cv::Scalar(0, 160, 0) : cv::Scalar(0, 0, 255), 2);
        cv::imwrite(base + "_boxes.jpg", vis);
        std::fprintf(stderr, "[offline] %s: %s 후보 %zu개 · 추출 %lld ms · 인코딩 %lld ms\n", f.c_str(),
                     q.valid ? "유효" : q.reason.c_str(), cands.size(),
                     (long long)std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count(),
                     (long long)std::chrono::duration_cast<std::chrono::milliseconds>(t2 - t1).count());
    }
    return 0;
}
