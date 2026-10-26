#pragma once
// 보조 박스 찾기: YOLOX-Nano 1클래스 "item". 판넬 차이로 못 나누는 붙은 물건과 판넬 색 물건을 메운다.
// ONNX 출력은 격자 디코딩까지 끝난 [1, N, 5+C] = cx, cy, w, h, obj, cls...
// 입력은 ROI 를 왼쪽 위 기준 레터박스(114 회색), BGR 0~255.
#include <algorithm>
#include <cmath>
#include <string>
#include <vector>
#include <opencv2/dnn.hpp>
#include <opencv2/imgproc.hpp>
#include "PanelExtractor.h"

struct DetectorParams {
    std::string model;          // 비면 쓰지 않는다
    int input = 416;
    float score = 0.7f;         // obj × cls. 여러 물건을 묶은 박스는 대개 이보다 낮다
    float nms = 0.5f;
    float minFill = 0.04f;      // fill 이 이보다 낮으면 빈 판넬로 보고 버린다 (0 = 끔)
};

struct Detection {
    cv::Rect box;               // 원본 픽셀
    float score = 0;
    float fill = 0;             // 박스 안 둘레와 다른 픽셀 비율
};

class ItemDetector {
public:
    explicit ItemDetector(DetectorParams p) : p(std::move(p)) {
        if (this->p.model.empty()) return;
        net = cv::dnn::readNetFromONNX(this->p.model);
        net.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
        net.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);
    }

    bool enabled() const { return !net.empty(); }
    const DetectorParams& params() const { return p; }

    std::vector<Detection> detect(const cv::Mat& bgr, cv::Rect roi) {
        std::vector<Detection> out;
        if (net.empty()) return out;
        roi = roi.area() > 0 ? (roi & cv::Rect({}, bgr.size())) : cv::Rect({}, bgr.size());
        cv::Mat crop = bgr(roi);
        float r = std::min((float)p.input / crop.cols, (float)p.input / crop.rows);
        cv::Mat padded(p.input, p.input, CV_8UC3, cv::Scalar(114, 114, 114)), resized;
        cv::resize(crop, resized, {std::max(1, (int)(crop.cols * r)), std::max(1, (int)(crop.rows * r))}, 0, 0, cv::INTER_LINEAR);
        resized.copyTo(padded(cv::Rect({}, resized.size())));
        net.setInput(cv::dnn::blobFromImage(padded, 1.0, {}, {}, false, false, CV_32F));
        cv::Mat pred = net.forward();                           // [1, N, 5+C]
        const int n = pred.size[1], k = pred.size[2];
        cv::Mat rows(n, k, CV_32F, pred.ptr<float>());
        std::vector<cv::Rect> boxes;
        std::vector<float> scores;
        for (int i = 0; i < n; ++i) {
            const float* d = rows.ptr<float>(i);
            float cls = *std::max_element(d + 5, d + k);
            float s = d[4] * cls;
            if (s < p.score) continue;
            float w = d[2] / r, h = d[3] / r;
            boxes.emplace_back((int)(d[0] / r - w / 2) + roi.x, (int)(d[1] / r - h / 2) + roi.y, (int)w, (int)h);
            scores.push_back(s);
        }
        std::vector<int> keep;
        cv::dnn::NMSBoxes(boxes, scores, p.score, p.nms, keep);
        keep = dropGroups(boxes, scores, keep);
        for (int i : keep) {
            cv::Rect b = boxes[i] & cv::Rect({}, bgr.size());
            if (b.width < 4 || b.height < 4) continue;
            float f = fill(bgr, b);
            if (f < p.minFill) continue;
            out.push_back({b, scores[i], f});
        }
        return out;
    }

    // 여러 물건을 묶은 박스 버리기. IoU 가 작아 NMS 로는 안 걸린다:
    // 점수가 더 높은 박스를 groupInside 이상 품고 그보다 groupArea 배 넘게 크면 버린다
    static std::vector<int> dropGroups(const std::vector<cv::Rect>& boxes, const std::vector<float>& scores, const std::vector<int>& keep) {
        constexpr float groupInside = 0.7f, groupArea = 1.5f;
        std::vector<int> out;
        for (int i : keep) {
            bool group = false;
            for (int j : keep) {
                if (j == i || scores[j] <= scores[i]) continue;
                float in = (float)(boxes[i] & boxes[j]).area() / (boxes[j].area() + 1e-6f);
                if (in >= groupInside && boxes[i].area() > groupArea * boxes[j].area()) { group = true; break; }
            }
            if (!group) out.push_back(i);
        }
        return out;
    }

    // 박스 안에서 둘레(중앙값)와 다른 픽셀 비율. 밝기 차 > 25, 색 차 > 6, 경계 > 70 (Lab 8비트)
    // 모델이 판넬 이음매 같은 빈 곳에도 높은 점수로 박스를 내서 거른다
    static float fill(const cv::Mat& bgr, const cv::Rect& box) {
        int m = std::max(8, std::min(box.width, box.height) / 6);
        cv::Rect outer = cv::Rect(box.x - m, box.y - m, box.width + 2 * m, box.height + 2 * m) & cv::Rect({}, bgr.size());
        cv::Mat lab;
        cv::cvtColor(bgr(outer), lab, cv::COLOR_BGR2Lab);
        cv::Rect inner = box - outer.tl();
        std::vector<uchar> ls, as, bs;
        for (int y = 0; y < lab.rows; y += 2) {
            const cv::Vec3b* row = lab.ptr<cv::Vec3b>(y);
            for (int x = 0; x < lab.cols; x += 2) {
                if (inner.contains({x, y})) continue;
                ls.push_back(row[x][0]); as.push_back(row[x][1]); bs.push_back(row[x][2]);
            }
        }
        if (ls.empty()) return 1;   // 박스가 화면 전체라 둘레가 없다
        auto med = [](std::vector<uchar>& v) { std::nth_element(v.begin(), v.begin() + v.size() / 2, v.end()); return (float)v[v.size() / 2]; };
        float rl = med(ls), ra = med(as), rb = med(bs);
        cv::Mat in = lab(inner), L;
        cv::extractChannel(in, L, 0);
        cv::Mat gx, gy, grad;
        cv::Sobel(L, gx, CV_32F, 1, 0, 3);
        cv::Sobel(L, gy, CV_32F, 0, 1, 3);
        cv::magnitude(gx, gy, grad);
        int hit = 0;
        for (int y = 0; y < in.rows; ++y) {
            const cv::Vec3b* row = in.ptr<cv::Vec3b>(y);
            const float* g = grad.ptr<float>(y);
            for (int x = 0; x < in.cols; ++x) {
                float dl = std::abs(row[x][0] - rl), dc = std::hypot(row[x][1] - ra, row[x][2] - rb);
                hit += dl > 25 || dc > 6 || g[x] > 70;
            }
        }
        return (float)hit / in.total();
    }

private:
    DetectorParams p;
    cv::dnn::Net net;
};

namespace detect {

inline float iou(const cv::Rect& a, const cv::Rect& b) {
    float inter = (float)(a & b).area();
    return inter / (a.area() + b.area() - inter + 1e-6f);
}

// b 가 a 안에 얼마나 들어가 있나 (b 넓이 대비)
inline float inside(const cv::Rect& a, const cv::Rect& b) { return (float)(a & b).area() / (b.area() + 1e-6f); }

inline Candidate fromDetection(const Detection& d, const char* source) {
    Candidate c;
    c.box = d.box;
    c.contrast = d.score;   // 모델 후보는 대비 대신 모델 점수
    c.fill = d.fill;
    c.source = source;
    return c;
}

// PanelExtractor 후보와 YOLOX 박스 합치기. 결과는 넓이 큰 순 (maxCandidates 로 자를 때 큰 것부터 남는다)
//   - 후보 하나가 YOLOX 박스 둘 이상을 품으면 그 박스들로 나눈다 (split)
//   - 후보가 YOLOX 박스 하나 안에 대부분 들어가면 그 박스로 바꾼다
//   - 어떤 후보와도 안 겹치는 YOLOX 박스는 더한다 (model)
//   - candidate_too_large · object_on_band · band_occluded 로 무효면 YOLOX 박스만으로 관측한다.
//     관측은 멈춘 장면에서만 하므로 띠를 가린 것은 손이 아니라 가장자리에 놓인 물건이다
inline std::vector<Candidate> merge(std::vector<Candidate> panel, SceneQuality& q, const std::vector<Detection>& dets) {
    // 판 가장자리 긁힘·그림자로 object_on_band 가 나도 아무것도 없으면 빈 판이다
    if (dets.empty() && panel.empty() && !q.valid && q.reason == "object_on_band") {
        q.valid = true;
        q.reason = "empty_by_model:object_on_band";
        return panel;
    }
    if (dets.empty()) return panel;
    std::vector<Candidate> out;
    if (!q.valid) {
        if (q.reason != "candidate_too_large" && q.reason != "object_on_band" && q.reason != "band_occluded") return panel;
        for (const auto& d : dets) out.push_back(fromDetection(d, "model"));
        q.valid = true;
        q.reason = "rescued_by_model:" + q.reason;
    } else {
        std::vector<bool> used(dets.size(), false);
        for (auto& c : panel) {
            std::vector<size_t> in;
            for (size_t i = 0; i < dets.size(); ++i)
                if (inside(c.box, dets[i].box) > 0.8f) in.push_back(i);
            if (in.size() >= 2) {
                for (size_t i : in) { out.push_back(fromDetection(dets[i], "split")); used[i] = true; }
                continue;
            }
            // 물건 일부만 잡힌 후보
            size_t whole = dets.size();
            for (size_t i = 0; i < dets.size(); ++i)
                if (inside(dets[i].box, c.box) > 0.7f && (whole == dets.size() || dets[i].box.area() < dets[whole].box.area())) whole = i;
            if (whole < dets.size()) {
                if (!used[whole]) out.push_back(fromDetection(dets[whole], "model"));
                used[whole] = true;
                continue;
            }
            for (size_t i = 0; i < dets.size(); ++i)
                if (iou(c.box, dets[i].box) >= 0.3f || inside(c.box, dets[i].box) > 0.8f) used[i] = true;
            out.push_back(c);
        }
        for (size_t i = 0; i < dets.size(); ++i)
            if (!used[i]) out.push_back(fromDetection(dets[i], "model"));
    }
    std::sort(out.begin(), out.end(), [](const Candidate& a, const Candidate& b) { return a.box.area() > b.box.area(); });
    return out;
}

}  // namespace detect
