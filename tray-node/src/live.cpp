// tray-detection-live: 카메라 화면을 보며 판넬 값을 맞추고 사진을 모으는 개발 도구 (통신 없음).
//
//   tray-detection-live [--roi x,y,w,h] [--size 1536x864] [--fps 10] [--settle N] [--save DIR] [--param k=v]...
//                       [--headless] [--encoder P --model M.onnx [--accept 0.8] [--margin 0.05]] [-- rpicam-vid 인자...]
//
//   키: s 저장 · r ROI 다시 고르기 · m 전경 마스크 · q/Esc 끝
//   멈출 때마다 결과를 한 줄 찍고, --save 면 그 프레임을 PNG 로 남긴다.
//   --model 이면 시연 모드: 박스 클릭이나 드래그로 등록, 오른쪽 클릭으로 모두 지움,
//   멈출 때마다 박스별로 가장 비슷한 등록 물건과 점수를 그린다 (accept·margin 은 시연용 값).
#include <chrono>
#include <csignal>
#include <cstdio>
#include <ctime>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>
#include <opencv2/highgui.hpp>
#include <opencv2/imgcodecs.hpp>
#include "Encoder.h"
#include "Overlay.h"
#include "PanelExtractor.h"
#include "RpicamSource.h"

using Clock = std::chrono::steady_clock;

static volatile std::sig_atomic_t stopRequested = 0;

// 등록 물건: L2 정규화한 벡터 + 작은 사진
struct DemoItem {
    cv::Mat vec, thumb;
};

struct DemoLabel {
    int item = -1;            // -1 = 없음
    float best = 0, second = 0;
};

static cv::Mat unit(const cv::Mat& v) {
    double n = cv::norm(v);
    return n > 1e-9 ? cv::Mat(v / n) : cv::Mat();
}

// 짧게 누르면 클릭, 끌면 네모
struct Mouse {
    cv::Point down{-1, -1};
    bool dragging = false;
    cv::Rect dragBox;                 // 끄는 중
    std::vector<cv::Rect> drags;
    std::vector<cv::Point> clicks;
    bool clear = false;
};

static void onMouse(int event, int x, int y, int, void* data) {
    auto& m = *static_cast<Mouse*>(data);
    if (event == cv::EVENT_LBUTTONDOWN) { m.down = {x, y}; m.dragging = true; m.dragBox = {}; }
    else if (event == cv::EVENT_MOUSEMOVE && m.dragging) m.dragBox = cv::Rect(m.down, cv::Point(x, y));
    else if (event == cv::EVENT_LBUTTONUP && m.dragging) {
        m.dragging = false;
        cv::Rect r(m.down, cv::Point(x, y));
        if (r.width > 15 && r.height > 15) m.drags.push_back(r);
        else m.clicks.push_back({x, y});
        m.dragBox = {};
    } else if (event == cv::EVENT_RBUTTONDOWN) m.clear = true;
}

static void drawDemo(cv::Mat& vis, const std::vector<Candidate>& cands, const std::vector<DemoLabel>& labels,
                     const std::vector<DemoItem>& items, float accept, float margin, const std::string& info) {
    for (size_t i = 0; i < cands.size() && i < labels.size(); ++i) {
        const auto& l = labels[i];
        if (l.item < 0) continue;
        bool ok = l.best >= accept && l.best - l.second >= margin;
        bool unknown = l.best < accept - 0.15f;
        cv::Scalar c = ok ? cv::Scalar(60, 200, 60) : unknown ? cv::Scalar(60, 60, 230) : cv::Scalar(0, 150, 255);
        char t[64];
        if (unknown) std::snprintf(t, sizeof t, "? %.2f", l.best);
        else std::snprintf(t, sizeof t, "#%d %.2f%s", l.item, l.best, ok ? "" : " ?");
        cv::Rect b = cands[i].box;
        cv::rectangle(vis, b, c, 5);
        int base = 0;
        cv::Size ts = cv::getTextSize(t, cv::FONT_HERSHEY_SIMPLEX, 1.1, 3, &base);
        cv::Point at(b.x, std::max(ts.height + 8, b.y - 8));
        cv::rectangle(vis, cv::Rect(at.x - 4, at.y - ts.height - 6, ts.width + 8, ts.height + 12), c, cv::FILLED);
        cv::putText(vis, t, at, cv::FONT_HERSHEY_SIMPLEX, 1.1, {255, 255, 255}, 3);
    }
    int s = 110, x = 10, y = vis.rows - s - 10;
    for (size_t i = 0; i < items.size() && x + s < vis.cols; ++i, x += s + 10) {
        cv::Mat t;
        cv::resize(items[i].thumb, t, {s, s});
        t.copyTo(vis(cv::Rect(x, y, s, s)));
        cv::rectangle(vis, cv::Rect(x, y, s, s), {255, 255, 255}, 2);
        cv::putText(vis, "#" + std::to_string(i), {x + 6, y + 30}, cv::FONT_HERSHEY_SIMPLEX, 0.9, {0, 0, 0}, 5);
        cv::putText(vis, "#" + std::to_string(i), {x + 6, y + 30}, cv::FONT_HERSHEY_SIMPLEX, 0.9, {255, 255, 255}, 2);
    }
    cv::rectangle(vis, cv::Rect(0, 44, vis.cols, 36), {30, 30, 30}, cv::FILLED);
    cv::putText(vis, info, {10, 70}, cv::FONT_HERSHEY_SIMPLEX, 0.75, {255, 255, 255}, 2);
}

static std::string stamp(uint64_t seq) {
    char t[32];
    std::time_t now = std::time(nullptr);
    std::strftime(t, sizeof t, "%Y%m%d-%H%M%S", std::localtime(&now));
    return std::string(t) + "-" + std::to_string(seq);
}

int main(int argc, char** argv) {
    int width = 1536, height = 864, fps = 10, settle = -1;
    bool headless = false;
    std::string saveDir, preset = "orbit_protonets_effb0_224", modelPath;
    float accept = 0.80f, margin = 0.05f;
    PanelParams params;
    std::vector<std::string> camArgs;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--") { camArgs.assign(argv + i + 1, argv + argc); break; }
        if (a == "--roi" && i + 1 < argc) {
            int x, y, w, h;
            if (std::sscanf(argv[++i], "%d,%d,%d,%d", &x, &y, &w, &h) != 4) { std::fprintf(stderr, "--roi x,y,w,h\n"); return 2; }
            params.roi = {x, y, w, h};
        } else if (a == "--size" && i + 1 < argc) {
            if (std::sscanf(argv[++i], "%dx%d", &width, &height) != 2) { std::fprintf(stderr, "--size WxH\n"); return 2; }
        } else if (a == "--fps" && i + 1 < argc) fps = std::atoi(argv[++i]);
        else if (a == "--settle" && i + 1 < argc) settle = std::atoi(argv[++i]);
        else if (a == "--save" && i + 1 < argc) saveDir = argv[++i];
        else if (a == "--headless") headless = true;
        else if (a == "--encoder" && i + 1 < argc) preset = argv[++i];
        else if (a == "--model" && i + 1 < argc) modelPath = argv[++i];
        else if (a == "--accept" && i + 1 < argc) accept = std::stof(argv[++i]);
        else if (a == "--margin" && i + 1 < argc) margin = std::stof(argv[++i]);
        else if (a == "--param" && i + 1 < argc) {
            if (!setPanelParam(params, argv[++i])) { std::fprintf(stderr, "모르는 값: %s\n", argv[i]); return 2; }
        } else {
            std::fprintf(stderr, "사용법: %s [--roi x,y,w,h] [--size WxH] [--fps N] [--settle 프레임] [--save DIR] "
                                 "[--param k=v]... [--headless] [--encoder 이름 --model M.onnx [--accept 0.8] [--margin 0.05]] "
                                 "[-- rpicam-vid 인자...]\n", argv[0]);
            return 2;
        }
    }
    if (width % 128 != 0) std::fprintf(stderr, "[live] 경고: 폭 %d 이 128 배수가 아니면 줄 여백 때문에 화면이 어긋날 수 있다\n", width);
    if (settle < 0) settle = fps;   // 기본 1초
    if (!saveDir.empty()) std::filesystem::create_directories(saveDir);

    std::unique_ptr<Encoder> encoder;
    if (!modelPath.empty()) {
        EncoderSpec spec;
        if (!encoderPreset(preset, spec)) { std::fprintf(stderr, "모르는 --encoder: %s\n", preset.c_str()); return 2; }
        encoder = std::make_unique<Encoder>(spec, modelPath);
        std::fprintf(stderr, "[live] 모델 시연 · %s\n", encoder->spaceId().c_str());
    }

    const char* win = "tray-detection-live";
    Mouse mouse;
    if (!headless) {
        cv::namedWindow(win, cv::WINDOW_NORMAL);
        cv::setWindowProperty(win, cv::WND_PROP_FULLSCREEN, cv::WINDOW_FULLSCREEN);
        if (encoder) cv::setMouseCallback(win, onMouse, &mouse);
    }
    std::vector<DemoItem> items;
    std::vector<DemoLabel> labels;
    std::string demoInfo = "click a box or drag a rectangle to register an item";

    // 신호를 받아도 rpicam-vid 를 정리하고 끝나게
    std::signal(SIGINT, [](int) { stopRequested = 1; });
    std::signal(SIGTERM, [](int) { stopRequested = 1; });
    RpicamSource cam(width, height, fps, camArgs);
    PanelExtractor extractor(params);
    Stillness still;
    int stillFrames = 0;
    bool changed = true, showMask = false;
    uint64_t seq = 0;
    cv::Mat frame;
    std::fprintf(stderr, "[live] %dx%d@%d, 멈춤 %d 프레임%s\n", width, height, fps, settle,
                 saveDir.empty() ? "" : (", 저장 " + saveDir).c_str());

    while (cam.running() && !stopRequested) {
        if (!cam.next(frame, seq)) continue;
        bool moving = still.moving(frame);
        auto t0 = Clock::now();
        SceneQuality q;
        cv::Mat mask;
        auto cands = extractor.find(frame, q, &mask);
        long long ms = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - t0).count();
        std::string status = overlay::describe(q, cands, ms);

        bool save = false;
        if (moving) {
            stillFrames = 0;
            changed = true;
        } else if (changed && ++stillFrames >= settle) {
            changed = false;
            std::printf("%s %s\n", stamp(seq).c_str(), status.c_str());
            for (size_t i = 0; i < cands.size(); ++i)
                std::printf("  %zu box=%d,%d,%d,%d contrast=%.1f fill=%.2f parts=%d\n", i, cands[i].box.x,
                            cands[i].box.y, cands[i].box.width, cands[i].box.height, cands[i].contrast, cands[i].fill,
                            cands[i].parts);
            std::fflush(stdout);
            save = !saveDir.empty();
            if (encoder && !items.empty() && q.valid) {
                auto e0 = Clock::now();
                labels.assign(cands.size(), {});
                for (size_t i = 0; i < cands.size(); ++i) {
                    cv::Mat v = unit(encoder->encode(frame, cands[i].box));
                    if (v.empty()) continue;
                    DemoLabel& l = labels[i];
                    for (size_t k = 0; k < items.size(); ++k) {
                        float sc = (float)v.dot(items[k].vec);
                        if (sc > l.best) { l.second = l.best; l.best = sc; l.item = (int)k; }
                        else if (sc > l.second) l.second = sc;
                    }
                }
                long long em = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - e0).count();
                char t[160];
                std::snprintf(t, sizeof t, "compared %zu boxes with %zu items in %lld ms  (green >= %.2f & gap >= %.2f, demo values)",
                              cands.size(), items.size(), em, accept, margin);
                demoInfo = t;
                for (size_t i = 0; i < labels.size(); ++i)
                    if (labels[i].item >= 0) std::printf("  %zu -> #%d %.3f (2nd %.3f)\n", i, labels[i].item, labels[i].best, labels[i].second);
                std::fflush(stdout);
            }
        }
        if (moving) labels.clear();

        if (encoder) {
            std::vector<cv::Rect> regs = mouse.drags;
            for (const auto& p : mouse.clicks)
                for (const auto& c : cands)
                    if (c.box.contains(p)) { regs.push_back(c.box); break; }
            mouse.drags.clear();
            mouse.clicks.clear();
            for (const auto& r : regs) {
                cv::Rect box = r & cv::Rect({}, frame.size());
                auto e0 = Clock::now();
                cv::Mat v = unit(encoder->encode(frame, box));
                if (v.empty()) continue;
                items.push_back({v, frame(Encoder::padded(box, frame.size())).clone()});
                char t[160];
                std::snprintf(t, sizeof t, "registered #%zu (%dx%d) in %lld ms - move things and wait 1s to compare",
                              items.size() - 1, box.width, box.height,
                              (long long)std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - e0).count());
                demoInfo = t;
                std::printf("[live] %s\n", t);
                changed = true;
                stillFrames = 0;
            }
            if (mouse.clear) { items.clear(); labels.clear(); mouse.clear = false; demoInfo = "cleared - click or drag to register"; }
        }

        int key = -1;
        if (!headless) {
            cv::Mat vis = frame.clone();
            overlay::draw(vis, extractor.params(), q, cands, status, moving, mask, showMask);
            if (encoder) {
                drawDemo(vis, cands, labels, items, accept, margin, demoInfo);
                if (mouse.dragging && mouse.dragBox.area() > 0) cv::rectangle(vis, mouse.dragBox, {0, 0, 255}, 4);
            }
            cv::imshow(win, vis);
            key = cv::waitKey(1) & 0xff;
        }
        if (key == 'q' || key == 27) break;
        if (key == 'm') showMask = !showMask;
        if (key == 's') save = true;
        if (key == 'r') {
            cv::Rect r = cv::selectROI(win, frame, true, false);
            if (r.area() > 0) {
                params.roi = r;
                extractor = PanelExtractor(params);
                std::printf("--roi %d,%d,%d,%d\n", r.x, r.y, r.width, r.height);
                std::fflush(stdout);
            }
        }
        if (save) {
            std::string path = saveDir.empty() ? stamp(seq) + ".png" : saveDir + "/" + stamp(seq) + ".png";
            cv::imwrite(path, frame);
            std::fprintf(stderr, "[live] 저장 %s\n", path.c_str());
        }
    }
    if (!cam.running() && !stopRequested) std::fprintf(stderr, "[live] 카메라가 멈췄다 (rpicam-vid 종료)\n");
    return 0;
}
