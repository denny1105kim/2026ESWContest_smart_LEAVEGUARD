#pragma once
// JSON 설정 (cv::FileStorage 로 읽는다). 예시: deploy/tray-detection.json
#include <string>
#include <vector>
#include <opencv2/core.hpp>
#include "Encoder.h"
#include "ItemDetector.h"
#include "PanelExtractor.h"

struct NodeConfig {
    std::string deviceId = "tray01";
    std::string encoderPreset = "orbit_protonets_effb0_224";
    std::string model = "/opt/leaveguard/models/orbit_protonets_effb0_224.onnx";
    EncoderSpec encoder;                            // encoderPreset 에서 채운다
    std::string encoder2Preset, model2;             // 선택. 특징을 이어 붙인다
    EncoderSpec encoder2;

    int width = 1536, height = 864, fps = 10;       // 폭은 128 배수 (RpicamSource 참고)
    std::vector<std::string> cameraArgs;            // rpicam-vid 에 그대로 넘긴다

    PanelParams panel;
    DetectorParams detector;                        // model 이 비면 PanelExtractor 만 쓴다
    std::string roiVersion = "full";                // 판넬 위치를 바꾸면 같이 바꾼다

    std::string mqttHost;                           // 비면 MQTT 를 쓰지 않는다
    int mqttPort = 1883;
    int healthSec = 5;

    std::string httpBind = "0.0.0.0";
    int httpPort = 8080;

    int settleFrames = 10;                          // 연속으로 멈춰 있어야 하는 프레임 수
    int refreshSec = 30;                            // 멈춘 장면도 이 간격으로 다시 관측
    int maxCandidates = 10;                         // 넓은 순. 인코딩 시간이 Pi5 의 프레임 나이 한도(3s)를 넘지 않게

    std::string outDir = "/var/lib/leaveguard-tray-detection";   // latest.json
    std::string saveDir;                            // 비면 안정 프레임을 저장하지 않는다
    int saveMax = 300;
};

// 파일에 없는 값은 기본값을 쓴다
inline bool loadConfig(const std::string& path, NodeConfig& c, std::string& error) {
    cv::FileStorage fs;
    try {
        fs.open(path, cv::FileStorage::READ | cv::FileStorage::FORMAT_JSON);
    } catch (const cv::Exception& e) {
        error = e.what();
        return false;
    }
    if (!fs.isOpened()) { error = "열 수 없음: " + path; return false; }

    auto str = [](const cv::FileNode& n, const char* k, std::string& v) { cv::FileNode x = n[k]; if (!x.empty() && x.isString()) v = (std::string)x; };
    auto num = [](const cv::FileNode& n, const char* k, int& v) { cv::FileNode x = n[k]; if (!x.empty()) v = (int)x; };

    cv::FileNode root = fs.root();
    str(root, "device_id", c.deviceId);
    if (!root["model"].empty()) { error = "model 대신 encoder.model 과 encoder.preset 을 쓴다"; return false; }
    cv::FileNode enc = root["encoder"];
    if (!enc.empty()) {
        str(enc, "preset", c.encoderPreset);
        str(enc, "model", c.model);
    }
    cv::FileNode enc2 = root["encoder2"];
    if (!enc2.empty()) {
        str(enc2, "preset", c.encoder2Preset);
        str(enc2, "model", c.model2);
    }
    str(root, "roi_version", c.roiVersion);
    str(root, "out_dir", c.outDir);
    str(root, "save_dir", c.saveDir);
    num(root, "save_max", c.saveMax);
    num(root, "settle_frames", c.settleFrames);
    num(root, "refresh_sec", c.refreshSec);
    num(root, "max_candidates", c.maxCandidates);

    cv::FileNode cam = root["camera"];
    if (!cam.empty()) {
        num(cam, "width", c.width);
        num(cam, "height", c.height);
        num(cam, "fps", c.fps);
        cv::FileNode args = cam["args"];
        for (auto it = args.begin(); it != args.end(); ++it) c.cameraArgs.push_back((std::string)*it);
    }

    cv::FileNode http = root["http"];
    if (!http.empty()) {
        str(http, "bind", c.httpBind);
        num(http, "port", c.httpPort);
    }

    cv::FileNode mq = root["mqtt"];
    if (!mq.empty()) {
        str(mq, "host", c.mqttHost);
        num(mq, "port", c.mqttPort);
        num(mq, "health_sec", c.healthSec);
    }

    cv::FileNode det = root["detector"];
    if (!det.empty()) {
        str(det, "model", c.detector.model);
        num(det, "input", c.detector.input);
        if (!det["score"].empty()) c.detector.score = (float)(double)det["score"];
        if (!det["nms"].empty()) c.detector.nms = (float)(double)det["nms"];
        if (!det["min_fill"].empty()) c.detector.minFill = (float)(double)det["min_fill"];
    }

    // 판넬 다각형 [[x, y], ...] (원본 픽셀). 있으면 roi 는 그 외접 사각형
    cv::FileNode poly = root["roi_polygon"];
    if (!poly.empty()) {
        for (auto it = poly.begin(); it != poly.end(); ++it) {
            std::vector<int> xy;
            (*it) >> xy;
            if (xy.size() != 2) { error = "roi_polygon 은 [[x, y], ...]"; return false; }
            c.panel.poly.emplace_back(xy[0], xy[1]);
        }
        if (c.panel.poly.size() < 3) { error = "roi_polygon 은 점 3개 이상"; return false; }
        c.panel.roi = cv::boundingRect(c.panel.poly);
    }

    cv::FileNode roi = root["roi"];
    if (!roi.empty() && c.panel.poly.empty()) {
        std::vector<int> v;
        roi >> v;
        if (v.size() != 4) { error = "roi 는 [x, y, w, h] 네 개"; return false; }
        c.panel.roi = cv::Rect(v[0], v[1], v[2], v[3]);
    }

    cv::FileNode panel = root["panel"];
    for (auto it = panel.begin(); it != panel.end(); ++it) {
        std::string name = (*it).name();
        if (!setPanelParam(c.panel, name + "=" + std::to_string((double)(*it).real()))) {
            error = "모르는 panel 값: " + name;
            return false;
        }
    }

    if (c.width % 128 != 0) { error = "camera.width 는 128 배수여야 한다 (줄 여백 때문에 화면이 어긋남)"; return false; }
    if (c.fps < 1 || c.fps > 30) { error = "camera.fps 는 1~30"; return false; }
    if (c.maxCandidates < 1) { error = "max_candidates 는 1 이상"; return false; }
    if (!encoderPreset(c.encoderPreset, c.encoder)) { error = "모르는 encoder.preset: " + c.encoderPreset; return false; }
    if (!c.encoder2Preset.empty() && !encoderPreset(c.encoder2Preset, c.encoder2)) { error = "모르는 encoder2.preset: " + c.encoder2Preset; return false; }
    return true;
}
