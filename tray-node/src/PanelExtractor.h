#pragma once
// 빈 판넬 사진 없이 물건 후보를 찾는다. 판넬 가장자리 띠(band)에는 물건이 없다고 보고,
// 매 프레임 띠에서 판넬 색(밝기 평면 + 색 중앙값, MAD)을 다시 재서 벗어난 픽셀과 밝기 경계를 전경으로 본다.
// 띠가 가려졌거나 판넬 색이 불안정하면 장면을 무효로 돌려준다 (후보 0개 = 물건 없음이 아니게).
#include <algorithm>
#include <cmath>
#include <string>
#include <vector>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

struct PanelParams {
    cv::Rect roi;                  // 판넬 영역 (원본 픽셀). 비어 있으면 화면 전체
    std::vector<cv::Point> poly;   // 판넬 다각형 (원본 픽셀). 있으면 다각형 밖은 안 본다
    float band = 0.05f;            // 띠 폭 (ROI 짧은 변 대비)
    int work = 640;                // 이 폭으로 줄여서 본다
    float lightSigma = 4.0f;       // 밝기 차이가 흩어짐(MAD)의 몇 배면 전경
    float chromaSigma = 4.0f;      // 색 차이가 흩어짐의 몇 배면 전경
    float lightFloor = 14.0f;      // 최소 밝기 차 (Lab L, 0~255)
    float chromaFloor = 8.0f;      // 색(a·b 거리) 최소 차이
    float edge = 40.0f;            // Sobel 경계 기준, 0 = 안 씀
    float minArea = 0.0015f;       // ROI 대비 이보다 작은 덩어리는 버림
    float mergeGap = 0.012f;       // ROI 대각선 대비 이 간격 안의 조각은 합친다
    float minBandInliers = 0.90f;  // 띠에서 판넬로 보이는 비율이 이보다 낮으면 무효
    float maxForeground = 0.45f;   // 전경 비율이 이보다 높으면 무효
    float maxCandidate = 0.5f;     // 후보 하나가 이 비율을 넘으면 무효
};

// "이름=값". 모르는 이름이면 false
inline bool setPanelParam(PanelParams& p, const std::string& kv) {
    auto eq = kv.find('=');
    if (eq == std::string::npos) return false;
    std::string k = kv.substr(0, eq);
    float v;
    try {
        v = std::stof(kv.substr(eq + 1));
    } catch (...) {
        return false;
    }
    if (k == "work") { p.work = (int)v; return true; }
    std::pair<const char*, float*> f[] = {
        {"band", &p.band}, {"lightSigma", &p.lightSigma}, {"chromaSigma", &p.chromaSigma},
        {"lightFloor", &p.lightFloor}, {"chromaFloor", &p.chromaFloor}, {"edge", &p.edge},
        {"minArea", &p.minArea}, {"mergeGap", &p.mergeGap}, {"minBandInliers", &p.minBandInliers},
        {"maxForeground", &p.maxForeground}, {"maxCandidate", &p.maxCandidate}};
    for (auto& [name, ptr] : f)
        if (k == name) { *ptr = v; return true; }
    return false;
}

// 다각형 판넬 마스크. 화면 가장자리에 닿은 변은 판이 화면 밖으로 이어지므로 띠를 두지 않는다
inline void panelMasks(const PanelParams& p, cv::Rect roi, double s, cv::Size size, int band, const cv::Size& frame, cv::Mat& inside, cv::Mat& bandMask) {
    inside = cv::Mat(size, CV_8U, cv::Scalar(0));
    std::vector<cv::Point> q;
    for (const auto& pt : p.poly) q.emplace_back((int)std::lround((pt.x - roi.x) * s), (int)std::lround((pt.y - roi.y) * s));
    cv::fillPoly(inside, std::vector<std::vector<cv::Point>>{q}, cv::Scalar(255));
    cv::Mat padded;
    int bx0 = roi.x == 0 ? band : 0, by0 = roi.y == 0 ? band : 0;
    int bx1 = roi.x + roi.width >= frame.width ? band : 0, by1 = roi.y + roi.height >= frame.height ? band : 0;
    cv::copyMakeBorder(inside, padded, by0, by1, bx0, bx1, cv::BORDER_REPLICATE);
    cv::erode(padded, padded, cv::getStructuringElement(cv::MORPH_ELLIPSE, {2 * band + 1, 2 * band + 1}), {-1, -1}, 1,
              cv::BORDER_CONSTANT, cv::Scalar(0));
    cv::Mat inner = padded(cv::Rect(bx0, by0, size.width, size.height));
    bandMask = inside & ~inner;
    inside = inner.clone();
}

// 박스 아래쪽(물건이 판에 닿는 곳)이 판 위이고 박스의 60% 이상이 판 안인가
inline bool onPanel(const PanelParams& p, const cv::Rect& box) {
    if (p.poly.empty()) return true;
    cv::Point2f foot(box.x + box.width * 0.5f, box.y + box.height * 0.85f);
    if (cv::pointPolygonTest(p.poly, foot, true) < -12) return false;
    int in = 0;
    for (int i = 0; i < 6; ++i)
        for (int j = 0; j < 6; ++j)
            in += cv::pointPolygonTest(p.poly, cv::Point2f(box.x + box.width * (i + 0.5f) / 6, box.y + box.height * (j + 0.5f) / 6), false) >= 0;
    return in >= 22;   // 36 칸 중 60%
}

struct Candidate {
    cv::Rect box;          // 원본 픽셀
    float contrast = 0;    // 판넬 대비 평균 세기 (MAD 배수)
    float fill = 0;        // 박스 안 전경 비율
    int parts = 1;         // 합친 조각 수
    std::string source = "panel";   // panel | model | split
};

struct SceneQuality {
    bool valid = false;
    std::string reason;
    float bandInliers = 0;
    float lightMad = 0, chromaMad = 0;
    float planeTilt = 0;         // ROI 끝에서 끝까지 L 차이
    float foreground = 0;
    float meanLight = 0;
};

class PanelExtractor {
public:
    explicit PanelExtractor(PanelParams p) : p(std::move(p)) {}

    const PanelParams& params() const { return p; }

    std::vector<Candidate> find(const cv::Mat& bgr, SceneQuality& q, cv::Mat* debugMask = nullptr) const {
        q = {};
        cv::Rect roi = !p.poly.empty() ? (cv::boundingRect(p.poly) & cv::Rect({}, bgr.size()))
                     : p.roi.area() > 0 ? (p.roi & cv::Rect({}, bgr.size())) : cv::Rect({}, bgr.size());
        if (roi.area() < 64 * 64) return fail(q, "roi_too_small");

        double s = std::min(1.0, (double)p.work / roi.width);
        cv::Mat small;
        cv::resize(bgr(roi), small, {}, s, s, cv::INTER_AREA);
        cv::Mat lab;
        cv::cvtColor(small, lab, cv::COLOR_BGR2Lab);
        std::vector<cv::Mat> ch;
        cv::split(lab, ch);
        cv::Mat L, A, B;
        ch[0].convertTo(L, CV_32F);
        ch[1].convertTo(A, CV_32F);
        ch[2].convertTo(B, CV_32F);

        int band = std::max(3, (int)std::lround(p.band * std::min(small.cols, small.rows)));
        cv::Mat bandMask(small.size(), CV_8U, cv::Scalar(255)), inside;
        if (p.poly.empty()) {
            bandMask(cv::Rect(band, band, small.cols - 2 * band, small.rows - 2 * band)).setTo(0);
            inside = ~bandMask;
        } else {
            panelMasks(p, roi, s, small.size(), band, bgr.size(), inside, bandMask);
        }

        // 띠로 판넬 모델: 밝기 평면 + 색 중앙값
        std::vector<cv::Point> pts;
        cv::findNonZero(bandMask, pts);
        if (pts.size() < 50) return fail(q, "band_empty");
        cv::Vec3d plane = fitPlane(L, pts);
        cv::Mat planeL = planeImage(plane, small.size());
        std::vector<float> dl, da, db;
        dl.reserve(pts.size()); da.reserve(pts.size()); db.reserve(pts.size());
        for (const auto& pt : pts) {
            dl.push_back(L.at<float>(pt) - planeL.at<float>(pt));
            da.push_back(A.at<float>(pt));
            db.push_back(B.at<float>(pt));
        }
        float ca = median(da), cb = median(db);
        for (auto& v : da) v -= ca;
        for (auto& v : db) v -= cb;
        q.lightMad = mad(dl);
        std::vector<float> dc(pts.size());
        for (size_t i = 0; i < pts.size(); ++i) dc[i] = std::hypot(da[i], db[i]);
        q.chromaMad = median(dc) * 1.4826f;
        q.planeTilt = (float)(std::abs(plane[1]) * small.cols + std::abs(plane[2]) * small.rows);
        q.meanLight = (float)cv::mean(planeL)[0];

        float lt = std::max(p.lightFloor, p.lightSigma * q.lightMad);
        float ct = std::max(p.chromaFloor, p.chromaSigma * q.chromaMad);

        // 비율만 보면 띠에 걸친 작은 물건은 통과하므로 뭉친 덩어리도 따로 본다
        int in = 0;
        cv::Mat bandOut(small.size(), CV_8U, cv::Scalar(0));
        for (size_t i = 0; i < pts.size(); ++i) {
            bool ok = std::abs(dl[i]) <= lt && dc[i] <= ct;
            in += ok;
            if (!ok) bandOut.at<uchar>(pts[i]) = 255;
        }
        q.bandInliers = pts.empty() ? 0 : (float)in / pts.size();
        if (q.bandInliers < p.minBandInliers) return fail(q, "band_occluded");
        cv::morphologyEx(bandOut, bandOut, cv::MORPH_OPEN, cv::getStructuringElement(cv::MORPH_ELLIPSE, {3, 3}));
        cv::Mat bl, bs, bc;
        int bn = cv::connectedComponentsWithStats(bandOut, bl, bs, bc, 8);
        for (int i = 1; i < bn; ++i)
            if (bs.at<int>(i, cv::CC_STAT_AREA) > p.minArea * 0.25 * small.total()) return fail(q, "object_on_band");
        if (q.meanLight < 15 || q.meanLight > 245) return fail(q, "exposure");

        // 판넬에서 벗어난 정도 (기준 배수), 밝기·색 중 큰 쪽
        cv::Mat lightDev = cv::abs(L - planeL) / lt;
        cv::Mat da2 = A - ca, db2 = B - cb, chromaDev;
        cv::magnitude(da2, db2, chromaDev);
        chromaDev /= ct;
        cv::Mat score = cv::max(lightDev, chromaDev);
        cv::GaussianBlur(score, score, {3, 3}, 0);
        cv::Mat mask = score > 1.0f;
        if (p.edge > 0) {
            cv::Mat gx, gy, grad;
            cv::Sobel(L, gx, CV_32F, 1, 0, 3);
            cv::Sobel(L, gy, CV_32F, 0, 1, 3);
            cv::magnitude(gx, gy, grad);
            mask |= grad > p.edge;
        }
        mask.setTo(0, ~inside);
        cv::morphologyEx(mask, mask, cv::MORPH_CLOSE, cv::getStructuringElement(cv::MORPH_ELLIPSE, {7, 7}));
        cv::morphologyEx(mask, mask, cv::MORPH_OPEN, cv::getStructuringElement(cv::MORPH_ELLIPSE, {3, 3}));
        fillHoles(mask);
        if (debugMask) *debugMask = mask.clone();

        int inner = cv::countNonZero(inside);
        q.foreground = inner > 0 ? (float)cv::countNonZero(mask) / inner : 1;
        if (q.foreground > p.maxForeground) return fail(q, "too_much_foreground");

        cv::Mat labels, stats, cents;
        int n = cv::connectedComponentsWithStats(mask, labels, stats, cents, 8);
        double minArea = p.minArea * small.total();
        struct Blob { cv::Rect box; double area; double score; int parts; };
        std::vector<Blob> blobs;
        for (int i = 1; i < n; ++i) {
            cv::Rect box(stats.at<int>(i, cv::CC_STAT_LEFT), stats.at<int>(i, cv::CC_STAT_TOP),
                         stats.at<int>(i, cv::CC_STAT_WIDTH), stats.at<int>(i, cv::CC_STAT_HEIGHT));
            double area = stats.at<int>(i, cv::CC_STAT_AREA);
            if (area < minArea * 0.25) continue;
            double sc = cv::mean(score(box), labels(box) == i)[0];
            blobs.push_back({box, area, sc * area, 1});
        }
        double gap = p.mergeGap * std::hypot(small.cols, small.rows);
        for (bool merged = true; merged;) {
            merged = false;
            for (size_t i = 0; i < blobs.size() && !merged; ++i)
                for (size_t j = i + 1; j < blobs.size() && !merged; ++j) {
                    cv::Rect a = blobs[i].box, b = blobs[j].box;
                    cv::Rect grown(a.x - (int)gap, a.y - (int)gap, a.width + 2 * (int)gap, a.height + 2 * (int)gap);
                    if ((grown & b).area() == 0) continue;
                    blobs[i] = {a | b, blobs[i].area + blobs[j].area, blobs[i].score + blobs[j].score, blobs[i].parts + blobs[j].parts};
                    blobs.erase(blobs.begin() + j);
                    merged = true;
                }
        }

        std::vector<Candidate> out;
        double innerBox = inner;
        for (const auto& b : blobs) {
            if (b.area < minArea) continue;
            if (b.box.area() > p.maxCandidate * innerBox) return fail(q, "candidate_too_large");
            Candidate c;
            c.box = cv::Rect(roi.x + (int)std::floor(b.box.x / s), roi.y + (int)std::floor(b.box.y / s),
                             (int)std::ceil(b.box.width / s), (int)std::ceil(b.box.height / s)) & cv::Rect({}, bgr.size());
            c.contrast = (float)(b.score / b.area);
            c.fill = (float)(b.area / b.box.area());
            c.parts = b.parts;
            out.push_back(c);
        }
        std::sort(out.begin(), out.end(), [](auto& a, auto& b) { return a.box.area() > b.box.area(); });
        q.valid = true;
        return out;
    }

private:
    static std::vector<Candidate> fail(SceneQuality& q, const char* why) {
        q.valid = false;
        q.reason = why;
        return {};
    }

    // L = a + b·x + c·y (최소제곱)
    static cv::Vec3d fitPlane(const cv::Mat& L, const std::vector<cv::Point>& pts) {
        cv::Mat X((int)pts.size(), 3, CV_64F), y((int)pts.size(), 1, CV_64F);
        for (int i = 0; i < (int)pts.size(); ++i) {
            X.at<double>(i, 0) = 1;
            X.at<double>(i, 1) = pts[i].x;
            X.at<double>(i, 2) = pts[i].y;
            y.at<double>(i, 0) = L.at<float>(pts[i]);
        }
        cv::Mat beta;
        cv::solve(X, y, beta, cv::DECOMP_SVD);
        return {beta.at<double>(0), beta.at<double>(1), beta.at<double>(2)};
    }

    static cv::Mat planeImage(const cv::Vec3d& p, const cv::Size& size) {
        cv::Mat out(size, CV_32F);
        for (int y = 0; y < size.height; ++y) {
            float* row = out.ptr<float>(y);
            for (int x = 0; x < size.width; ++x) row[x] = (float)(p[0] + p[1] * x + p[2] * y);
        }
        return out;
    }

    static float median(std::vector<float> v) {
        if (v.empty()) return 0;
        auto mid = v.begin() + v.size() / 2;
        std::nth_element(v.begin(), mid, v.end());
        return *mid;
    }

    static float mad(const std::vector<float>& v) {
        float m = median(v);
        std::vector<float> d(v.size());
        for (size_t i = 0; i < v.size(); ++i) d[i] = std::abs(v[i] - m);
        return median(d) * 1.4826f;
    }

    // 물건 무늬가 판넬 색과 같아 생긴 구멍을 메운다
    static void fillHoles(cv::Mat& mask) {
        std::vector<std::vector<cv::Point>> outer;
        cv::findContours(mask.clone(), outer, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
        cv::drawContours(mask, outer, -1, 255, cv::FILLED);
    }

    PanelParams p;
};

// 직전 프레임과의 평균 차이로 움직임을 본다
class Stillness {
public:
    static constexpr double MOVING = 2.0;   // 0~255, 센서 잡음은 1 정도

    bool moving(const cv::Mat& img) {
        cv::Mat small;
        cv::resize(img, small, {160, 120}, 0, 0, cv::INTER_AREA);
        cv::cvtColor(small, small, cv::COLOR_BGR2GRAY);
        if (previous.empty()) {
            previous = small;
            return true;
        }
        cv::Mat d;
        cv::absdiff(small, previous, d);
        previous = small;
        return cv::mean(d)[0] > MOVING;
    }

    void reset() { previous.release(); }

private:
    cv::Mat previous;
};
