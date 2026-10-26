#pragma once
// 후보·판넬 영역·장면 상태를 프레임 위에 그린다 (HTTP 미리보기, live 도구).
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>
#include <opencv2/imgproc.hpp>
#include "PanelExtractor.h"

namespace overlay {

inline std::string describe(const SceneQuality& q, const std::vector<Candidate>& cands, long long ms) {
    char line[256];
    std::snprintf(line, sizeof line, "%s cand=%zu band=%.2f lightMad=%.1f chromaMad=%.1f fg=%.3f L=%.0f %lldms",
                  q.valid ? "valid" : q.reason.c_str(), cands.size(), q.bandInliers, q.lightMad, q.chromaMad,
                  q.foreground, q.meanLight, ms);
    return line;
}

inline void draw(cv::Mat& vis, const PanelParams& p, const SceneQuality& q, const std::vector<Candidate>& cands,
                 const std::string& status, bool moving, const cv::Mat& mask, bool showMask) {
    cv::Rect roi = !p.poly.empty() ? (cv::boundingRect(p.poly) & cv::Rect({}, vis.size()))
                 : p.roi.area() > 0 ? (p.roi & cv::Rect({}, vis.size())) : cv::Rect({}, vis.size());
    int band = std::max(3, (int)std::lround(p.band * std::min(roi.width, roi.height)));
    if (!p.poly.empty()) {
        // 파랑 = 판넬 다각형, 노랑 = 띠 안쪽 경계
        cv::polylines(vis, std::vector<std::vector<cv::Point>>{p.poly}, true, {255, 200, 0}, 2);
        // 안쪽 경계는 큰 커널로 깎아 구해서 느리다. 판 설정이 같으면 한 번만 구한다
        thread_local std::vector<cv::Point> cachedPoly;
        thread_local cv::Size cachedSize;
        thread_local int cachedBand = -1;
        thread_local std::vector<std::vector<cv::Point>> cs;
        if (cachedPoly != p.poly || cachedSize != vis.size() || cachedBand != band) {
            cv::Mat inside, bandMask;
            panelMasks(p, roi, 1.0, roi.size(), band, vis.size(), inside, bandMask);
            cs.clear();
            cv::findContours(inside, cs, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE, roi.tl());
            cachedPoly = p.poly;
            cachedSize = vis.size();
            cachedBand = band;
        }
        cv::polylines(vis, cs, true, {0, 220, 255}, 1);
    } else {
        cv::rectangle(vis, roi, {255, 200, 0}, 2);
        cv::rectangle(vis, cv::Rect(roi.x + band, roi.y + band, roi.width - 2 * band, roi.height - 2 * band), {0, 220, 255}, 1);
    }
    for (size_t i = 0; i < cands.size(); ++i) {
        cv::rectangle(vis, cands[i].box, {0, 0, 255}, 3);
        char t[48];
        std::snprintf(t, sizeof t, "%zu c%.1f p%d", i, cands[i].contrast, cands[i].parts);
        cv::putText(vis, t, cands[i].box.tl() + cv::Point(4, 26), cv::FONT_HERSHEY_SIMPLEX, 0.8, {0, 0, 255}, 2);
    }
    if (showMask && !mask.empty()) {
        cv::Mat m, m3;
        cv::resize(mask, m, {vis.cols / 3, vis.cols / 3 * mask.rows / mask.cols}, 0, 0, cv::INTER_NEAREST);
        cv::cvtColor(m, m3, cv::COLOR_GRAY2BGR);
        m3.copyTo(vis(cv::Rect(vis.cols - m3.cols, vis.rows - m3.rows, m3.cols, m3.rows)));
    }
    cv::rectangle(vis, cv::Rect(0, 0, vis.cols, 44), {0, 0, 0}, cv::FILLED);
    cv::putText(vis, (moving ? "[moving] " : "") + status, {10, 31}, cv::FONT_HERSHEY_SIMPLEX, 0.85,
                q.valid ? cv::Scalar(80, 255, 80) : cv::Scalar(80, 80, 255), 2);
}

// 마지막 관측에서 특징을 뽑은 박스. 움직이는 중에는 박스가 옛 자리라 그리지 않는다
inline void drawModel(cv::Mat& vis, const std::vector<cv::Rect>& boxes, const std::string& info, double ageSec, bool moving) {
    const cv::Scalar green(70, 200, 70);
    if (!moving)
        for (size_t i = 0; i < boxes.size(); ++i) {
            cv::rectangle(vis, boxes[i], green, 4);
            std::string t = "#" + std::to_string(i) + " feature";
            int base = 0;
            cv::Size ts = cv::getTextSize(t, cv::FONT_HERSHEY_SIMPLEX, 0.8, 2, &base);
            cv::Point at(boxes[i].x, std::max(ts.height + 50, boxes[i].y - 6));
            cv::rectangle(vis, cv::Rect(at.x, at.y - ts.height - 6, ts.width + 8, ts.height + 12), green, cv::FILLED);
            cv::putText(vis, t, at + cv::Point(4, 0), cv::FONT_HERSHEY_SIMPLEX, 0.8, {255, 255, 255}, 2);
        }
    if (info.empty()) return;
    char age[48];
    std::snprintf(age, sizeof age, "  (%.0fs ago)", ageSec);
    cv::rectangle(vis, cv::Rect(0, vis.rows - 44, vis.cols, 44), {20, 20, 20}, cv::FILLED);
    cv::putText(vis, info + age, {10, vis.rows - 14}, cv::FONT_HERSHEY_SIMPLEX, 0.8, {120, 255, 120}, 2);
}

}  // namespace overlay
