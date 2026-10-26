// leaveguard_vision: camera and face models for the wallpad app, driven over stdin/stdout. Logs go to stderr.
//
//   <- ready <model version>
//   -> preview <s> [camera]          camera on, keep writing the preview file (registration)
//   -> scan <s> [camera]             camera on, preview + judge every frame (lookup)
//   -> snap <s> <l> <t> <r> <b>      judge the current preview frame, face must be inside the box (0~1)
//   -> track <s> <l> <t> <r> <b>     report head pose every preview frame
//   -> stop <s>                      camera off, or close the door session
//   -> door <s> <0|1>                open the door-camera session (1 = also extract features)
//   -> jpeg <s> <path>               judge one door-camera JPEG
//
//   <- <s> started
//   <- <s> frame <w> <h> <path>                 BGRA preview, mirrored
//   <- <s> face <f1,f2,...> <yaw> <pitch>       door adds <liveness 0~1>
//   <- <s> pose <yaw> <pitch> <0|1>             1 = sharp and well lit
//   <- <s> none | many | outside | poor
//   <- <s> seen <n> <x> <y> <w> <h> <rot>       door: face count, largest box (0~1, not mirrored) in the
//                                               frame rotated clockwise by rot; then face | poor | many if door 1
//   <- <s> bad                                  door: JPEG unreadable
//   <- <s> error camera                         open failed or no frame for 5 s
#include <csignal>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <vector>
#include "Camera.h"
#include "Face.h"
#include "Jpeg.h"
#include "Preview.h"
#include "Protocol.h"

using Clock = std::chrono::steady_clock;

// 카메라를 닫지 않고 죽으면 다음 실행에서 SetFormat 이 실패하므로 신호를 받으면 정상 종료한다
static volatile sig_atomic_t g_stop = 0;

// 박스 중심이 guide 안에 있고, guide 를 가로세로 15% 넘게 벗어나지 않아야 한다
static bool inside(const cv::Mat& img, const cv::Mat& row, const cv::Rect2f& guide) {
    cv::Rect2f box(row.at<float>(0, 0) / img.cols, row.at<float>(0, 1) / img.rows,
                   row.at<float>(0, 2) / img.cols, row.at<float>(0, 3) / img.rows);
    cv::Point2f center(box.x + box.width / 2, box.y + box.height / 2);
    float mx = guide.width * 0.15f, my = guide.height * 0.15f;
    return guide.contains(center)
        && box.x >= guide.x - mx && box.br().x <= guide.br().x + mx
        && box.y >= guide.y - my && box.br().y <= guide.br().y + my;
}

static std::string judge(Face& face, const cv::Mat& img, const cv::Rect2f& guide, bool picky = false) {
    auto faces = face.detect(img);
    if (faces.empty()) return "none";
    if (faces.size() > 1) return "many";
    if (!inside(img, faces[0], guide)) return "outside";
    if (picky && !Face::usable(img, faces[0])) return "poor";
    HeadPose p = Face::pose(img, faces[0]);
    char angles[48];
    std::snprintf(angles, sizeof angles, " %.1f %.1f", p.yaw, p.pitch);
    return "face " + numbers(face.feature(img, faces[0])) + angles;
}

static std::string posed(Face& face, const cv::Mat& img, const cv::Rect2f& guide) {
    auto faces = face.detect(img);
    if (faces.empty()) return "none";
    if (faces.size() > 1) return "many";
    if (!inside(img, faces[0], guide)) return "outside";
    HeadPose p = Face::pose(img, faces[0]);
    if (!p.ok) return "none";
    bool steady = Face::sharpAndLit(img, faces[0]);
    static int n = 0;
    if (++n % 5 == 0) std::fprintf(stderr, "[vision] pose yaw %.1f pitch %.1f steady %d\n", p.yaw, p.pitch, steady ? 1 : 0);
    char out[64];
    std::snprintf(out, sizeof out, "pose %.1f %.1f %d", p.yaw, p.pitch, steady ? 1 : 0);
    return out;
}

static cv::Mat turned(const cv::Mat& img, int rot) {
    cv::Mat out;
    switch (rot) {
        case 90:  cv::rotate(img, out, cv::ROTATE_90_CLOCKWISE); return out;
        case 180: cv::rotate(img, out, cv::ROTATE_180); return out;
        case 270: cv::rotate(img, out, cv::ROTATE_90_COUNTERCLOCKWISE); return out;
        default:  return img;
    }
}

// 현관 카메라는 뒤집혀 달릴 수 있어 얼굴이 없으면 다른 방향도 본다. 찾은 방향을 먼저 시도한다
static void judgeDoor(Face& face, const cv::Mat& src, int session, bool recognize) {
    static int lastRot = 0;
    std::vector<int> order = {lastRot};
    for (int r : {0, 180, 90, 270}) if (r != lastRot) order.push_back(r);
    std::vector<cv::Mat> faces;
    cv::Mat img;
    int rot = lastRot;
    for (int r : order) {
        img = turned(src, r);
        faces = face.detect(img);
        if (!faces.empty()) { rot = r; break; }
    }
    if (faces.empty()) return say(session, "none");
    lastRot = rot;
    const cv::Mat* big = &faces[0];
    for (const auto& f : faces) if (f.at<float>(0, 2) > big->at<float>(0, 2)) big = &f;
    char box[112];
    std::snprintf(box, sizeof box, "seen %zu %.3f %.3f %.3f %.3f %d", faces.size(),
                  big->at<float>(0, 0) / img.cols, big->at<float>(0, 1) / img.rows,
                  big->at<float>(0, 2) / img.cols, big->at<float>(0, 3) / img.rows, rot);
    say(session, box);
    if (!recognize) return;
    if (faces.size() > 1) return say(session, "many");
    if (!Face::usable(img, faces[0])) return say(session, "poor");
    HeadPose p = Face::pose(img, faces[0]);
    float live = face.liveness(img, faces[0]);
    static int n = 0;
    if (++n % 6 == 0) std::fprintf(stderr, "[vision] door live %.2f\n", live);
    char tail[64];
    std::snprintf(tail, sizeof tail, " %.1f %.1f %.2f", p.yaw, p.pitch, live);
    say(session, "face " + numbers(face.feature(img, faces[0])) + tail);
}

int main() {
    Face face("models");
    const char* cache = std::getenv("XDG_CACHE_HOME");
    Preview preview(std::string(cache ? cache : "/tmp") + "/preview.bgra");
    std::printf("ready %s\n", Face::VERSION);
    std::fflush(stdout);

    std::unique_ptr<Camera> camera;
    std::string mode;                               // preview | scan
    bool started = false;
    int session = 0;
    Clock::time_point openedAt;
    cv::Mat last;                                   // snap 용
    bool tracking = false;
    cv::Rect2f trackGuide{0, 0, 1, 1};
    int doorSession = 0;                            // 0 = 없음, 카메라 세션과 동시에 열릴 수 있다
    bool doorRecognize = false;

    auto closeCamera = [&] {
        camera.reset();
        last.release();
        preview.clear();
    };

    signal(SIGTERM, [](int) { g_stop = 1; });
    signal(SIGINT, [](int) { g_stop = 1; });

    while (!g_stop) {
        std::vector<Command> commands;
        if (!readCommands(commands, camera ? 0 : 200)) break;

        for (const auto& c : commands) {
            if (c.name == "preview" || c.name == "scan") {
                closeCamera();
                try {
                    camera = std::make_unique<Camera>(c.arg);
                } catch (const std::exception& e) {
                    std::fprintf(stderr, "[vision] 카메라 실패: %s\n", e.what());
                    say(c.session, "error camera");
                    continue;
                }
                mode = c.name;
                session = c.session;
                tracking = false;
                started = false;
                openedAt = Clock::now();
                std::fprintf(stderr, "[vision] %d %s %s\n", session, c.name.c_str(), c.arg.c_str());
            } else if (c.name == "door") {
                doorSession = c.session;
                doorRecognize = c.arg == "1";
                std::fprintf(stderr, "[vision] %d door %s\n", doorSession, doorRecognize ? "recognize" : "detect");
            } else if (c.name == "jpeg" && c.session == doorSession && doorSession) {
                cv::Mat img = readJpeg(c.arg);
                if (img.empty()) say(c.session, "bad");
                else judgeDoor(face, img, c.session, doorRecognize);
            } else if (c.name == "stop" && c.session == doorSession && doorSession) {
                doorSession = 0;
                std::fprintf(stderr, "[vision] door stop\n");
            } else if (c.name == "snap") {
                bool ready = camera && mode == "preview" && c.session == session && !last.empty();
                say(c.session, ready ? judge(face, last, c.guide) : "error camera");
            } else if (c.name == "track" && camera && mode == "preview" && c.session == session) {
                tracking = true;
                trackGuide = c.guide;
            } else if (c.name == "stop" && camera && c.session == session) {
                closeCamera();
                std::fprintf(stderr, "[vision] %d stop\n", session);
            }
        }
        if (!camera) continue;

        cv::Mat img = camera->read();
        if (img.empty()) {
            if (!started && Clock::now() - openedAt > std::chrono::seconds(5)) {
                closeCamera();
                say(session, "error camera");
            }
            continue;
        }
        if (!started) {
            started = true;
            say(session, "started");
        }

        last = img;
        preview.write(img);
        say(session, "frame 320 240 " + preview.path());
        if (mode == "scan") say(session, judge(face, img, {0, 0, 1, 1}, /*picky=*/true));
        else if (tracking) say(session, posed(face, img, trackGuide));
    }
    closeCamera();
    return 0;
}
