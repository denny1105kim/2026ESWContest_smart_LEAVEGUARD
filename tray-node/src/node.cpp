// tray-detection: 트레이 카메라 -> 박스 찾기 -> 특징 -> 관측 JSON (MQTT · HTTP · out_dir/latest.json)
//
//   tray-detection [--config /etc/leaveguard/tray-detection.json]
//
// 매 프레임 움직임과 박스를 보고, settle_frames 동안 멈춰 있으면 박스를 인코딩해 관측을 낸다.
// 같은 자리·같은 그림의 박스는 이전 벡터를 다시 쓴다.
//
// HTTP:
//   GET  /                                     미리보기 + 상태 페이지
//   GET  /health                               상태 JSON
//   GET  /latest.json                          마지막 관측
//   GET  /preview.mjpeg · /preview.jpg         후보를 그린 영상 / 한 장
//   GET  /raw.mjpeg                            박스 없는 영상 (960 폭, X-Frame-Seq)
//   GET  /snapshot.jpg[?frame_id=N]            원본 한 장 (X-Frame-Seq)
//   GET  /crop.jpg?frame_id=N&x=&y=&w=&h=      박스 하나 (여백 포함, 긴 변 <= 320)
//   POST /encode?frame_id=N&x=&y=&w=&h=[&save=1][&rot=90|180|270]
//                                              박스 하나의 특징. save=1 이면 out_dir/redbox/ 에 남긴다. rot 은 돌려서 본 특징
//   POST /rescan[?request_id=ID]               요청 이후 찍힌 프레임으로 다시 관측
//   POST /setup?on=1|0                         세팅 모드 (30fps 원본 영상, 인식 멈춤, 10분 뒤 자동 해제)
//   GET  /board · POST /board?pts=x_y_x_y_x_y_x_y · POST /board?clear=1
//                                              판 네 모서리(왼위 · 오른위 · 오른아래 · 왼아래, 원본 픽셀).
//                                              있으면 그 사각형을 화면에 꽉 차게 펴서 트레이로 본다
#include <algorithm>
#include <cctype>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <deque>
#include <filesystem>
#include <fstream>
#include <memory>
#include <mutex>
#include <random>
#include <sstream>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include "Config.h"
#include "Encoder.h"
#include "Http.h"
#include "Mqtt.h"
#include "Observation.h"
#include "Overlay.h"
#include "ItemDetector.h"
#include "PanelExtractor.h"
#include "RpicamSource.h"

using Clock = std::chrono::steady_clock;
namespace fs = std::filesystem;

static volatile std::sig_atomic_t stopRequested = 0;

static long long monoNs(Clock::time_point t) {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(t.time_since_epoch()).count();
}

static long long msSince(Clock::time_point t) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - t).count();
}

static std::string isoUtc(std::chrono::system_clock::time_point tp) {
    std::time_t t = std::chrono::system_clock::to_time_t(tp);
    long ms = std::chrono::duration_cast<std::chrono::milliseconds>(tp.time_since_epoch()).count() % 1000;
    std::tm tm{};
    gmtime_r(&t, &tm);
    char buf[40];
    std::strftime(buf, sizeof buf, "%Y-%m-%dT%H:%M:%S", &tm);
    char out[56];
    std::snprintf(out, sizeof out, "%s.%03ldZ", buf, ms);
    return out;
}

// boot_id 로 쓰는 실행 ID. 서비스만 재시작해도 순번이 1부터 다시 시작할 수 있게 실행마다 새로 만든다
static std::string randomHex(int n) {
    std::random_device rd;
    std::string s;
    for (int i = 0; i < n; ++i) s += "0123456789abcdef"[rd() % 16];
    return s;
}

static double cpuTempC() {
    std::ifstream f("/sys/class/thermal/thermal_zone0/temp");
    double v = 0;
    return (f >> v) ? v / 1000.0 : -1;
}

static double iou(const cv::Rect& a, const cv::Rect& b) {
    double inter = (a & b).area();
    double uni = a.area() + b.area() - inter;
    return uni > 0 ? inter / uni : 0;
}

// 벡터 재사용 판단용 작은 그림
static cv::Mat thumbOf(const cv::Mat& bgr, const cv::Rect& box) {
    cv::Rect r = Encoder::padded(box, bgr.size());
    if (r.width < 8 || r.height < 8) return {};
    cv::Mat g, t;
    cv::cvtColor(bgr(r), g, cv::COLOR_BGR2GRAY);
    cv::resize(g, t, {32, 32}, 0, 0, cv::INTER_AREA);
    return t;
}

// 외부 ID 는 로그·JSON 에 그대로 들어가므로 안전한 글자만 남긴다
static std::string safeId(const std::string& v) {
    std::string clean;
    for (char c : v)
        if (std::isalnum((unsigned char)c) || c == '-' || c == '_' || c == '.') clean += c;
    return clean.substr(0, 64);
}

static std::string queryValue(const std::string& query, const std::string& key) {
    std::string k = key + "=";
    size_t p = query.find(k);
    while (p != std::string::npos && p > 0 && query[p - 1] != '&') p = query.find(k, p + 1);
    if (p == std::string::npos) return "";
    size_t e = query.find('&', p);
    return safeId(query.substr(p + k.size(), e == std::string::npos ? std::string::npos : e - p - k.size()));
}

// MQTT command 에서 "key":"value" 하나 (명령 형식이 고정이라 파서 없이)
static std::string jsonString(const std::string& text, const std::string& key) {
    size_t k = text.find("\"" + key + "\"");
    if (k == std::string::npos) return "";
    size_t a = text.find('"', text.find(':', k) + 1);
    size_t b = a == std::string::npos ? a : text.find('"', a + 1);
    if (b == std::string::npos) return "";
    return safeId(text.substr(a + 1, b - a - 1));
}

struct Cached {
    cv::Rect box;
    cv::Mat thumb, vec;
};

struct PreviewState {
    std::shared_ptr<const cv::Mat> frame;
    uint64_t frameSeq = 0;
    std::vector<Candidate> cands;
    SceneQuality q;
    bool moving = true;
    std::string status;
    std::vector<cv::Rect> encodedBoxes;   // 마지막 관측에서 특징을 뽑은 박스
    std::string modelInfo;
    Clock::time_point modelAt;
    PanelParams panel;
    bool setup = false;
    std::vector<cv::Point2f> board;
};

// 처리 스레드와 HTTP · MQTT 스레드가 함께 보는 값. 프레임은 통째로 바꾸고 읽는 쪽은 포인터만 쥔다
struct Shared {
    std::mutex m;
    PreviewState view;
    std::string latestObs = "";
    std::string health = "{}";
    long long rescanAtNs = 0;     // 이보다 뒤에 찍힌 프레임으로만 관측
    std::string rescanRequestId;
    bool setup = false;
    Clock::time_point setupUntil;
    std::vector<cv::Point2f> board;
    bool boardChanged = false;
    // 관측 프레임을 최근 kKeep 장 남겨 frame_id 로 사진·특징을 다시 받을 수 있게 한다
    static constexpr size_t kKeep = 16;   // 1536x864 BGR 약 4MB 씩
    std::deque<std::pair<uint64_t, std::shared_ptr<const cv::Mat>>> kept;

    void keep(uint64_t id, std::shared_ptr<const cv::Mat> f) {
        std::lock_guard<std::mutex> lk(m);
        kept.emplace_back(id, std::move(f));
        while (kept.size() > kKeep) kept.pop_front();
    }

    std::shared_ptr<const cv::Mat> frameAt(uint64_t id) {
        std::lock_guard<std::mutex> lk(m);
        if (view.frame && view.frameSeq == id) return view.frame;
        for (const auto& [k, f] : kept)
            if (k == id) return f;
        return nullptr;
    }

    PreviewState snapshot() {
        std::lock_guard<std::mutex> lk(m);
        return view;
    }

    void requestRescan(const std::string& requestId) {
        std::lock_guard<std::mutex> lk(m);
        rescanAtNs = monoNs(Clock::now());
        rescanRequestId = requestId;
    }
};

static std::vector<cv::Point2f> loadBoard(const std::string& path) {
    std::ifstream f(path);
    std::vector<cv::Point2f> pts;
    float x, y;
    while (pts.size() < 4 && (f >> x >> y)) pts.emplace_back(x, y);
    return pts.size() == 4 ? pts : std::vector<cv::Point2f>{};
}

static bool saveBoard(const std::string& path, const std::vector<cv::Point2f>& pts) {
    std::error_code ec;
    if (pts.empty()) return fs::remove(path, ec) || !fs::exists(path);
    std::ofstream f(path, std::ios::trunc);
    for (const auto& p : pts) f << p.x << " " << p.y << "\n";
    return (bool)f;
}

static PanelParams boardPanel(PanelParams p, cv::Size size) {
    int m = std::max(4, (int)std::lround(0.01 * std::min(size.width, size.height)));
    p.poly = {{m, m}, {size.width - 1 - m, m}, {size.width - 1 - m, size.height - 1 - m}, {m, size.height - 1 - m}};
    p.roi = cv::boundingRect(p.poly);
    return p;
}

static cv::Mat renderPreview(const PreviewState& s) {
    cv::Mat vis = s.frame->clone();
    if (s.setup) {
        if (s.board.size() == 4) {
            std::vector<cv::Point> q;
            for (const auto& p : s.board) q.emplace_back((int)std::lround(p.x), (int)std::lround(p.y));
            cv::polylines(vis, std::vector<std::vector<cv::Point>>{q}, true, {40, 40, 255}, 3);
        }
        cv::rectangle(vis, cv::Rect(0, 0, vis.cols, 44), {0, 0, 0}, cv::FILLED);
        cv::putText(vis, s.status, {10, 31}, cv::FONT_HERSHEY_SIMPLEX, 0.85, {80, 200, 255}, 2);
        return vis;
    }
    overlay::draw(vis, s.panel, s.q, s.cands, s.status, s.moving, cv::Mat(), false);
    overlay::drawModel(vis, s.encodedBoxes, s.modelInfo, std::chrono::duration<double>(Clock::now() - s.modelAt).count(), s.moving);
    return vis;
}

static void streamMjpeg(int fd, HttpServer& srv, Shared& sh) {
    const char* hdr = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
    if (!HttpServer::writeAll(fd, hdr, std::strlen(hdr))) return;
    uint64_t last = 0;
    while (srv.running && !stopRequested) {
        PreviewState s = sh.snapshot();
        if (!s.frame || s.frameSeq == last) { usleep(50000); continue; }
        last = s.frameSeq;
        // 새 프레임이 올 때만 보내 카메라 속도를 따른다. 960 폭으로 줄여 인코딩 · Wi-Fi 부담을 덜어 준다
        cv::Mat vis = renderPreview(s), small;
        cv::resize(vis, small, {960, vis.rows * 960 / vis.cols}, 0, 0, cv::INTER_AREA);
        std::vector<uchar> jpg;
        cv::imencode(".jpg", small, jpg, {cv::IMWRITE_JPEG_QUALITY, 75});
        std::string part = "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: " + std::to_string(jpg.size()) + "\r\n\r\n";
        if (!HttpServer::writeAll(fd, part.data(), part.size()) ||
            !HttpServer::writeAll(fd, (const char*)jpg.data(), jpg.size()) || !HttpServer::writeAll(fd, "\r\n", 2))
            return;
    }
}

// 월패드 Wi-Fi 가 원본 크기 MJPEG 를 못 버텨 960 폭으로 줄인다
static void streamRaw(int fd, HttpServer& srv, Shared& sh) {
    const char* hdr = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
    if (!HttpServer::writeAll(fd, hdr, std::strlen(hdr))) return;
    uint64_t last = 0;
    while (srv.running && !stopRequested) {
        PreviewState s = sh.snapshot();
        if (!s.frame || s.frameSeq == last) { usleep(50000); continue; }
        last = s.frameSeq;
        cv::Mat small;
        cv::resize(*s.frame, small, {960, s.frame->rows * 960 / s.frame->cols}, 0, 0, cv::INTER_AREA);
        std::vector<uchar> jpg;
        cv::imencode(".jpg", small, jpg, {cv::IMWRITE_JPEG_QUALITY, 75});
        std::string part = "--frame\r\nContent-Type: image/jpeg\r\nX-Frame-Seq: " + std::to_string(s.frameSeq) +
                           "\r\nContent-Length: " + std::to_string(jpg.size()) + "\r\n\r\n";
        if (!HttpServer::writeAll(fd, part.data(), part.size()) ||
            !HttpServer::writeAll(fd, (const char*)jpg.data(), jpg.size()) || !HttpServer::writeAll(fd, "\r\n", 2))
            return;
    }
}

static bool queryBox(const std::string& query, const cv::Size& size, cv::Rect& box) {
    try {
        box = cv::Rect(std::stoi(queryValue(query, "x")), std::stoi(queryValue(query, "y")), std::stoi(queryValue(query, "w")),
                       std::stoi(queryValue(query, "h"))) & cv::Rect({}, size);
    } catch (...) {
        return false;
    }
    return box.width >= 8 && box.height >= 8;
}

// 사람이 그린 박스(자동 탐지가 놓친 물건)를 재학습용으로 남긴다
static void saveRedBox(const std::string& outDir, const cv::Mat& frame, uint64_t frameId, const cv::Rect& box) {
    std::error_code ec;
    std::string dir = outDir + "/redbox";
    fs::create_directories(dir, ec);
    std::string base = dir + "/" + isoUtc(std::chrono::system_clock::now()).substr(0, 19) + "-" + std::to_string(frameId);
    std::replace(base.begin(), base.end(), ':', '-');
    cv::imwrite(base + ".jpg", frame, {cv::IMWRITE_JPEG_QUALITY, 95});
    std::ofstream(base + ".json", std::ios::trunc) << "{\"frame_id\":" << frameId << ",\"bbox\":[" << box.x << "," << box.y << ","
                                                   << box.width << "," << box.height << "]}\n";
}

// 안정 프레임과 관측을 남긴다. 오래된 것부터 지워 saveMax 장만 둔다
static void saveSample(const NodeConfig& cfg, const cv::Mat& frame, const std::string& json, uint64_t sequence) {
    std::error_code ec;
    std::string base = cfg.saveDir + "/" + isoUtc(std::chrono::system_clock::now()).substr(0, 19) + "-" + std::to_string(sequence);
    std::replace(base.begin(), base.end(), ':', '-');
    cv::imwrite(base + ".jpg", frame, {cv::IMWRITE_JPEG_QUALITY, 95});
    std::ofstream(base + ".json", std::ios::trunc) << json << "\n";
    std::vector<fs::path> files;
    for (const auto& e : fs::directory_iterator(cfg.saveDir, ec))
        if (e.path().extension() == ".jpg") files.push_back(e.path());
    if ((int)files.size() <= cfg.saveMax) return;
    std::sort(files.begin(), files.end());   // 파일 이름이 시각 순
    for (size_t i = 0; i + cfg.saveMax < files.size(); ++i) {
        fs::remove(files[i], ec);
        fs::remove(fs::path(files[i]).replace_extension(".json"), ec);
    }
}

static const char* INDEX_HTML = R"HTML(<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>트레이 카메라</title>
<style>
body{margin:0;background:#111;color:#ddd;font:14px system-ui,sans-serif}
#bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:10px}
button{font:inherit;padding:10px 16px;border:0;border-radius:8px;background:#333;color:#eee;cursor:pointer}
button.on{background:#d33;color:#fff}button.go{background:#2a7;color:#fff}button:disabled{opacity:.35;cursor:default}
#msg{color:#9cf;margin-left:4px}
#wrap{position:relative;max-width:1536px}
#v{width:100%;display:block}
#ov{position:absolute;inset:0;width:100%;height:100%;touch-action:none}
.h{fill:#f33;stroke:#fff;stroke-width:2;cursor:grab}
pre{padding:8px;margin:0;font:12px monospace;color:#999}
</style>
<div id=bar>
<button id=setup>세팅 모드 켜기</button>
<button id=box disabled>빨간 박스로 판 잡기</button>
<button id=save class=go disabled>판 저장</button>
<button id=clear disabled>판 잡기 해제</button>
<span id=msg></span>
</div>
<div id=wrap><img id=v src=/preview.mjpeg><svg id=ov></svg></div>
<pre id=s></pre>
<script>
const $=id=>document.getElementById(id),ov=$('ov'),NS='http://www.w3.org/2000/svg';
let st={setup:false,width:1536,height:864,points:[]},edit=false,pts=[],drag=-1;
function msg(t){$('msg').textContent=t}
async function load(){try{st=await(await fetch('/board')).json()}catch(e){return}
 $('setup').textContent=st.setup?'세팅 모드 끄기':'세팅 모드 켜기';$('setup').classList.toggle('on',st.setup);
 $('box').disabled=!st.setup;$('clear').disabled=!st.setup||!st.points.length;$('save').disabled=!st.setup||!edit;
 if(!st.setup&&edit){edit=false;draw()}
 if(st.setup&&!edit)msg('세팅 중 · 남은 시간 '+Math.floor(st.setup_left_s/60)+':'+String(st.setup_left_s%60).padStart(2,'0')+(st.points.length?' · 저장된 판 있음 (빨간 선)':' · 저장된 판 없음'))
 else if(!st.setup)msg(st.points.length?'판을 화면에 꽉 차게 펴서 인식 중':'판 잡기 없음 · 원본 화면으로 인식 중')}
function draw(){ov.innerHTML='';if(!edit)return;ov.setAttribute('viewBox','0 0 '+st.width+' '+st.height);
 const pg=document.createElementNS(NS,'polygon');pg.setAttribute('points',pts.map(p=>p.join(',')).join(' '));
 pg.setAttribute('fill','rgba(255,50,50,.12)');pg.setAttribute('stroke','#f33');pg.setAttribute('stroke-width','4');ov.appendChild(pg);
 pts.forEach((p,i)=>{const c=document.createElementNS(NS,'circle');c.setAttribute('cx',p[0]);c.setAttribute('cy',p[1]);c.setAttribute('r',22);c.setAttribute('class','h');
  c.addEventListener('pointerdown',e=>{drag=i;ov.setPointerCapture(e.pointerId);e.preventDefault()});ov.appendChild(c)})}
function at(e){const r=ov.getBoundingClientRect();return[Math.round((e.clientX-r.left)/r.width*st.width),Math.round((e.clientY-r.top)/r.height*st.height)]}
ov.addEventListener('pointermove',e=>{if(drag<0)return;const p=at(e);pts[drag]=[Math.max(0,Math.min(st.width-1,p[0])),Math.max(0,Math.min(st.height-1,p[1]))];draw()});
ov.addEventListener('pointerup',()=>drag=-1);
$('setup').onclick=async()=>{const on=!st.setup;msg(on?'카메라를 30fps 로 다시 여는 중…':'원래 설정으로 돌아가는 중…');
 await fetch('/setup?on='+(on?1:0),{method:'POST'});edit=false;draw();setTimeout(()=>{$('v').src='/preview.mjpeg?'+Date.now();load()},2500)};
$('box').onclick=()=>{edit=!edit;if(edit){const w=st.width,h=st.height;
 pts=st.points.length==4?st.points.map(p=>[Math.round(p[0]),Math.round(p[1])]):[[w*.15,h*.15],[w*.85,h*.15],[w*.85,h*.85],[w*.15,h*.85]].map(p=>p.map(Math.round));
 msg('빨간 점 네 개를 판 모서리로 끌어 맞추세요 (왼위 · 오른위 · 오른아래 · 왼아래)')}draw();load()};
$('save').onclick=async()=>{const r=await fetch('/board?pts='+pts.flat().join('_'),{method:'POST'});
 if(r.ok){edit=false;draw();msg('저장했어요. 세팅 모드를 끄면 이 판을 화면에 꽉 차게 펴서 인식해요')}else msg('저장 실패: '+(await r.text()));load()};
$('clear').onclick=async()=>{if(!confirm('판 잡기를 해제할까요? 원본 화면으로 인식합니다'))return;await fetch('/board?clear=1',{method:'POST'});edit=false;draw();load()};
load();setInterval(load,1000);
setInterval(async()=>{try{$('s').textContent=JSON.stringify(await(await fetch('/health')).json(),null,1)}catch(e){}},1000);
</script>
)HTML";

int main(int argc, char** argv) {
    std::string configPath = "/etc/leaveguard/tray-detection.json";
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--config" && i + 1 < argc) configPath = argv[++i];
        else { std::fprintf(stderr, "사용법: %s [--config 파일.json]\n", argv[0]); return 2; }
    }
    std::signal(SIGPIPE, SIG_IGN);
    std::signal(SIGINT, [](int) { stopRequested = 1; });
    std::signal(SIGTERM, [](int) { stopRequested = 1; });

    NodeConfig cfg;
    if (fs::exists(configPath)) {
        std::string err;
        if (!loadConfig(configPath, cfg, err)) { std::fprintf(stderr, "[node] 설정 오류 (%s): %s\n", configPath.c_str(), err.c_str()); return 2; }
        std::fprintf(stderr, "[node] 설정 %s\n", configPath.c_str());
    } else {
        encoderPreset(cfg.encoderPreset, cfg.encoder);
        std::fprintf(stderr, "[node] 설정 파일 없음 (%s) — 기본값으로 시작\n", configPath.c_str());
    }

    std::unique_ptr<Encoder> encoder;
    try {
        auto t0 = Clock::now();
        encoder = std::make_unique<Encoder>(cfg.encoder, cfg.model);
        if (!cfg.encoder2Preset.empty()) encoder->addSecond(cfg.encoder2, cfg.model2);
        std::fprintf(stderr, "[node] 모델 로드 %lld ms · 특징 공간 %s\n", msSince(t0), encoder->spaceId().c_str());
    } catch (const std::exception& e) {
        std::fprintf(stderr, "[node] 모델을 못 읽음 (%s, %s): %s\n", cfg.encoderPreset.c_str(), cfg.model.c_str(), e.what());
        return 3;
    }

    std::error_code ec;
    fs::create_directories(cfg.outDir, ec);
    const bool outOk = !ec;
    if (!outOk) std::fprintf(stderr, "[node] out_dir 못 만듦 (%s) — latest.json 파일은 쓰지 않는다\n", cfg.outDir.c_str());
    if (!cfg.saveDir.empty()) fs::create_directories(cfg.saveDir, ec);

    const std::string runId = randomHex(12);
    const auto startedAt = Clock::now();
    Shared sh;
    const std::string boardPath = cfg.outDir + "/board.txt";
    const cv::Size frameSize(cfg.width, cfg.height);
    std::vector<cv::Point2f> board = loadBoard(boardPath);
    PanelParams panel = cfg.panel;
    cv::Mat warp;
    auto applyBoard = [&] {
        if (board.size() == 4) {
            std::vector<cv::Point2f> dst = {{0, 0}, {(float)cfg.width, 0}, {(float)cfg.width, (float)cfg.height}, {0, (float)cfg.height}};
            warp = cv::getPerspectiveTransform(board, dst);
            panel = boardPanel(cfg.panel, frameSize);
        } else {
            warp.release();
            panel = cfg.panel;
        }
    };
    applyBoard();
    sh.board = board;
    if (!warp.empty()) std::fprintf(stderr, "[node] 판 모서리 %s — 판을 화면에 꽉 차게 편다\n", boardPath.c_str());
    PanelExtractor extractor(panel);
    ItemDetector detector(cfg.detector);
    if (detector.enabled())
        std::fprintf(stderr, "[node] 보조 박스 찾기 %s (점수 %.2f)\n", cfg.detector.model.c_str(), cfg.detector.score);
    Stillness still;

    // frame_id 가 없으면 지금 프레임
    auto frameFor = [&](const std::string& query, uint64_t& id) -> std::shared_ptr<const cv::Mat> {
        std::string v = queryValue(query, "frame_id");
        if (v.empty()) {
            PreviewState s = sh.snapshot();
            id = s.frameSeq;
            return s.frame;
        }
        try { id = std::stoull(v); } catch (...) { return nullptr; }
        return sh.frameAt(id);
    };

    HttpServer http(cfg.httpBind, cfg.httpPort, [&](int fd, const HttpRequest& req) {
        if (req.path == "/encode") {
            if (req.method != "POST") return HttpServer::respond(fd, 405, "text/plain", "POST only\n");
            uint64_t id = 0;
            auto f = frameFor(req.query, id);
            if (!f) return HttpServer::respond(fd, 404, "application/json", "{\"error\":\"frame gone\"}\n");
            cv::Rect box;
            if (!queryBox(req.query, f->size(), box)) return HttpServer::respond(fd, 400, "application/json", "{\"error\":\"bad box\"}\n");
            const std::string rot = queryValue(req.query, "rot");
            if (!rot.empty() && rot != "90" && rot != "180" && rot != "270")
                return HttpServer::respond(fd, 400, "application/json", "{\"error\":\"bad rot\"}\n");
            cv::Mat v = rot.empty() ? encoder->encode(*f, box) : encoder->encodeRotated(*f, box, std::stoi(rot));
            if (v.empty()) return HttpServer::respond(fd, 500, "application/json", "{\"error\":\"encode failed\"}\n");
            if (queryValue(req.query, "save") == "1") saveRedBox(cfg.outDir, *f, id, box);
            std::fprintf(stderr, "[http] 박스 인코딩 frame %llu [%d,%d,%d,%d]\n", (unsigned long long)id, box.x, box.y, box.width, box.height);
            std::ostringstream o;
            o << "{\"frame_id\":" << id << ",\"bbox\":[" << box.x << "," << box.y << "," << box.width << "," << box.height << "]"
              << ",\"embedding_space_id\":" << obs::quote(encoder->spaceId()) << ",\"embedding_dim\":" << encoder->dim()
              << ",\"dtype\":\"f32le\",\"l2_normalized\":" << (encoder->l2() ? "true" : "false")
              << ",\"embedding\":" << obs::quote(obs::vector64(v)) << "}\n";
            return HttpServer::respond(fd, 200, "application/json", o.str());
        }
        if (req.path == "/rescan") {
            if (req.method != "POST") return HttpServer::respond(fd, 405, "text/plain", "POST only\n");
            sh.requestRescan(queryValue(req.query, "request_id"));
            return HttpServer::respond(fd, 202, "application/json", "{\"requested\":true}\n");
        }
        if (req.path == "/setup") {
            if (req.method != "POST") return HttpServer::respond(fd, 405, "text/plain", "POST only\n");
            bool on = queryValue(req.query, "on") == "1";
            std::lock_guard<std::mutex> lk(sh.m);
            sh.setup = on;
            sh.setupUntil = Clock::now() + std::chrono::minutes(10);
            std::fprintf(stderr, "[http] 세팅 모드 %s\n", on ? "켬" : "끔");
            return HttpServer::respond(fd, 200, "application/json", std::string("{\"setup\":") + (on ? "true" : "false") + "}\n");
        }
        if (req.path == "/board" && req.method == "POST") {
            std::vector<cv::Point2f> pts;
            if (queryValue(req.query, "clear") != "1") {
                std::string v = queryValue(req.query, "pts");
                std::vector<float> n;
                std::stringstream ss(v);
                std::string t;
                while (std::getline(ss, t, '_')) {
                    try { n.push_back(std::stof(t)); } catch (...) { return HttpServer::respond(fd, 400, "application/json", "{\"error\":\"bad pts\"}\n"); }
                }
                if (n.size() != 8) return HttpServer::respond(fd, 400, "application/json", "{\"error\":\"need 4 points\"}\n");
                for (int k = 0; k < 4; ++k)
                    pts.emplace_back(std::clamp(n[2 * k], 0.f, (float)cfg.width - 1), std::clamp(n[2 * k + 1], 0.f, (float)cfg.height - 1));
                if (std::fabs(cv::contourArea(pts)) < 0.05 * cfg.width * cfg.height)
                    return HttpServer::respond(fd, 400, "application/json", "{\"error\":\"board too small\"}\n");
            }
            if (!saveBoard(boardPath, pts)) return HttpServer::respond(fd, 500, "application/json", "{\"error\":\"save failed\"}\n");
            {
                std::lock_guard<std::mutex> lk(sh.m);
                sh.board = pts;
                sh.boardChanged = true;
            }
            std::fprintf(stderr, "[http] 판 모서리 %s\n", pts.empty() ? "해제" : "저장");
            return HttpServer::respond(fd, 200, "application/json", std::string("{\"board\":") + (pts.empty() ? "false" : "true") + "}\n");
        }
        if (req.method != "GET") return HttpServer::respond(fd, 405, "text/plain", "GET only\n");
        if (req.path == "/board") {
            std::ostringstream o;
            std::lock_guard<std::mutex> lk(sh.m);
            long left = sh.setup ? (long)std::chrono::duration_cast<std::chrono::seconds>(sh.setupUntil - Clock::now()).count() : 0;
            o << "{\"setup\":" << (sh.setup ? "true" : "false") << ",\"setup_left_s\":" << std::max(0L, left)
              << ",\"width\":" << cfg.width << ",\"height\":" << cfg.height << ",\"points\":[";
            for (size_t k = 0; k < sh.board.size(); ++k) o << (k ? "," : "") << "[" << sh.board[k].x << "," << sh.board[k].y << "]";
            o << "]}\n";
            return HttpServer::respond(fd, 200, "application/json", o.str());
        }
        if (req.path == "/") return HttpServer::respond(fd, 200, "text/html; charset=utf-8", INDEX_HTML);
        if (req.path == "/health") {
            std::lock_guard<std::mutex> lk(sh.m);
            return HttpServer::respond(fd, 200, "application/json", sh.health + "\n");
        }
        if (req.path == "/latest.json") {
            std::lock_guard<std::mutex> lk(sh.m);
            if (sh.latestObs.empty()) return HttpServer::respond(fd, 404, "application/json", "{\"error\":\"no observation yet\"}\n");
            return HttpServer::respond(fd, 200, "application/json", sh.latestObs + "\n");
        }
        if (req.path == "/preview.mjpeg") return streamMjpeg(fd, http, sh);
        if (req.path == "/raw.mjpeg") return streamRaw(fd, http, sh);
        if (req.path == "/crop.jpg" || (req.path == "/snapshot.jpg" && !queryValue(req.query, "frame_id").empty())) {
            uint64_t id = 0;
            auto f = frameFor(req.query, id);
            if (!f) return HttpServer::respond(fd, 404, "application/json", "{\"error\":\"frame gone\"}\n");
            cv::Mat out = *f;
            if (req.path == "/crop.jpg") {
                cv::Rect box;
                if (!queryBox(req.query, f->size(), box)) return HttpServer::respond(fd, 400, "application/json", "{\"error\":\"bad box\"}\n");
                cv::Rect r = Encoder::padded(box, f->size());
                double k = std::min(1.0, 320.0 / std::max(r.width, r.height));
                cv::resize((*f)(r), out, {}, k, k, cv::INTER_AREA);
            }
            std::vector<uchar> jpg;
            cv::imencode(".jpg", out, jpg, {cv::IMWRITE_JPEG_QUALITY, 90});
            return HttpServer::respond(fd, 200, "image/jpeg", std::string((const char*)jpg.data(), jpg.size()),
                                       "X-Frame-Seq: " + std::to_string(id) + "\r\n");
        }
        if (req.path == "/snapshot.jpg" || req.path == "/preview.jpg") {
            PreviewState s = sh.snapshot();
            if (!s.frame) return HttpServer::respond(fd, 404, "application/json", "{\"error\":\"no frame yet\"}\n");
            bool annotated = req.path == "/preview.jpg";
            std::vector<uchar> jpg;
            cv::imencode(".jpg", annotated ? renderPreview(s) : *s.frame, jpg, {cv::IMWRITE_JPEG_QUALITY, annotated ? 80 : 92});
            return HttpServer::respond(fd, 200, "image/jpeg", std::string((const char*)jpg.data(), jpg.size()),
                                       "X-Frame-Seq: " + std::to_string(s.frameSeq) + "\r\n");
        }
        HttpServer::respond(fd, 404, "text/plain", "not found\n");
    });
    if (!http.start()) std::fprintf(stderr, "[node] HTTP 없이 계속한다\n");

    // {"cmd":"rescan","request_id":"..."} 또는 "rescan". POST /rescan 과 같다
    std::unique_ptr<MqttLink> mqtt;
    if (!cfg.mqttHost.empty()) {
        mqtt = std::make_unique<MqttLink>(cfg.mqttHost, cfg.mqttPort, "tray-detection-" + cfg.deviceId,
                                          "leaveguard/belongings/" + cfg.deviceId, [&](const std::string& payload) {
            std::string cmd = payload == "rescan" ? payload : jsonString(payload, "cmd");
            if (cmd != "rescan") { std::fprintf(stderr, "[mqtt] 모르는 명령: %.80s\n", payload.c_str()); return; }
            std::string id = jsonString(payload, "request_id");
            sh.requestRescan(id);
            std::fprintf(stderr, "[mqtt] 재검사 요청%s%s\n", id.empty() ? "" : " ", id.c_str());
        });
        if (!mqtt->start()) { std::fprintf(stderr, "[node] MQTT 를 만들 수 없음 — MQTT 없이 계속한다\n"); mqtt.reset(); }
    } else {
        std::fprintf(stderr, "[node] mqtt.host 없음 — MQTT 없이 (HTTP·파일만)\n");
    }

    std::unique_ptr<RpicamSource> cam;
    bool inSetup = false;
    auto openCamera = [&] {
        cam = std::make_unique<RpicamSource>(cfg.width, cfg.height, inSetup ? 30 : cfg.fps, cfg.cameraArgs);
        still.reset();
    };
    openCamera();
    std::fprintf(stderr, "[node] 카메라 %dx%d@%d · 멈춤 %d프레임 · 갱신 %ds · 박스 최대 %d · HTTP %s:%d · 실행 ID %s\n", cfg.width,
                 cfg.height, cfg.fps, cfg.settleFrames, cfg.refreshSec, cfg.maxCandidates, cfg.httpBind.c_str(), cfg.httpPort, runId.c_str());

    uint64_t sequence = 0, frameSeq = 0;
    int stillFrames = 0;
    bool changed = true;
    int burst = 0;
    size_t lastBoxes = 0;
    auto lastObsAt = Clock::now() - std::chrono::hours(1);
    auto lastFrameAt = Clock::now();
    auto lastHealth = Clock::now() - std::chrono::hours(1);
    auto lastMqttHealth = lastHealth;
    auto fpsWindow = Clock::now();
    int fpsCount = 0;
    double fps = 0;
    long long extractMs = 0, encodeMs = 0, detectMs = 0;
    int lastEncoded = 0, lastReused = 0;
    bool truncated = false;
    std::vector<Cached> cache;

    while (!stopRequested) {
        auto now = Clock::now();
        bool wantSetup, boardChanged;
        {
            std::lock_guard<std::mutex> lk(sh.m);
            if (sh.setup && now > sh.setupUntil) {
                sh.setup = false;
                std::fprintf(stderr, "[node] 세팅 모드 10분 지나 자동 해제\n");
            }
            wantSetup = sh.setup;
            boardChanged = sh.boardChanged;
            sh.boardChanged = false;
            if (boardChanged) board = sh.board;
        }
        if (boardChanged) {
            applyBoard();
            extractor = PanelExtractor(panel);
            cache.clear();
            changed = true;
            still.reset();
        }
        if (wantSetup != inSetup) {
            inSetup = wantSetup;
            std::fprintf(stderr, "[node] 세팅 모드 %s — 카메라 %dfps 로 다시 연다\n", inSetup ? "시작" : "끝", inSetup ? 30 : cfg.fps);
            cam.reset();
            openCamera();
            lastFrameAt = Clock::now();
            stillFrames = 0;
            changed = true;
            continue;
        }
        if (!cam->running() || now - lastFrameAt > std::chrono::seconds(5)) {
            std::fprintf(stderr, "[node] 카메라가 멈췄다 — 다시 연다\n");
            std::string health = "{\"device_id\":" + obs::quote(cfg.deviceId) + ",\"run_id\":" + obs::quote(runId) +
                                 ",\"state\":\"camera_down\",\"camera_running\":false,\"sequence\":" + std::to_string(sequence) + "}";
            {
                std::lock_guard<std::mutex> lk(sh.m);
                sh.view.status = "camera_down";
                sh.health = health;
            }
            if (mqtt) mqtt->publish("health", health, 0, false);
            cam.reset();
            for (int i = 0; i < 20 && !stopRequested; ++i) usleep(100000);
            if (stopRequested) break;
            openCamera();
            lastFrameAt = Clock::now();
            continue;
        }

        cv::Mat frame;
        uint64_t camSeq;
        Clock::time_point capT;
        if (!cam->next(frame, camSeq, 1000, &capT)) continue;
        lastFrameAt = Clock::now();
        ++fpsCount;
        if (lastFrameAt - fpsWindow >= std::chrono::seconds(2)) {
            fps = fpsCount / std::chrono::duration<double>(lastFrameAt - fpsWindow).count();
            fpsCount = 0;
            fpsWindow = lastFrameAt;
        }

        if (inSetup) {
            long left;
            {
                std::lock_guard<std::mutex> lk(sh.m);
                left = std::max(0L, (long)std::chrono::duration_cast<std::chrono::seconds>(sh.setupUntil - Clock::now()).count());
                auto& v = sh.view;
                v.frame = std::make_shared<const cv::Mat>(frame);
                v.frameSeq = ++frameSeq;
                v.setup = true;
                v.board = sh.board;
                v.cands.clear();
                char t[120];
                std::snprintf(t, sizeof t, "SETUP  %.0f fps  |  auto off in %ld:%02ld  |  detection paused", fps, left / 60, left % 60);
                v.status = t;
            }
            if (Clock::now() - lastHealth >= std::chrono::seconds(1)) {
                lastHealth = Clock::now();
                std::string health = "{\"device_id\":" + obs::quote(cfg.deviceId) + ",\"run_id\":" + obs::quote(runId) +
                                     ",\"state\":\"setup\",\"camera_running\":true,\"fps\":" + std::to_string((int)fps) +
                                     ",\"setup_left_s\":" + std::to_string(left) + ",\"cpu_temp_c\":" + std::to_string((int)cpuTempC()) + "}";
                std::lock_guard<std::mutex> lk(sh.m);
                sh.health = health;
            }
            continue;
        }
        if (!warp.empty()) {
            cv::Mat flat;
            cv::warpPerspective(frame, flat, warp, frameSize, cv::INTER_LINEAR, cv::BORDER_REPLICATE);
            frame = flat;
        }

        bool moving = still.moving(frame);
        auto e0 = Clock::now();
        SceneQuality q;
        std::vector<Candidate> cands = extractor.find(frame, q);
        extractMs = msSince(e0);

        if (moving) { stillFrames = 0; changed = true; }
        else ++stillFrames;

        // 관측 조건: 움직인 뒤 안정 · 재검사 요청 · 갱신 주기
        bool settled = !moving && stillFrames >= cfg.settleFrames;
        std::string requestId;
        bool rescan = false;
        {
            std::lock_guard<std::mutex> lk(sh.m);
            rescan = sh.rescanAtNs > 0 && monoNs(capT) > sh.rescanAtNs;
            if (rescan && settled) requestId = sh.rescanRequestId;
            sh.view.frame = std::make_shared<const cv::Mat>(frame);   // frame 은 반복마다 새 Mat 이라 공유해도 된다
            sh.view.frameSeq = ++frameSeq;
            sh.view.cands = cands;
            sh.view.q = q;
            sh.view.moving = moving;
            sh.view.status = overlay::describe(q, cands, extractMs);
            sh.view.panel = panel;
            sh.view.setup = false;
        }
        auto every = burst > 0 ? std::chrono::milliseconds(400) : std::chrono::milliseconds(cfg.refreshSec * 1000);
        bool due = settled && (changed || rescan || now - lastObsAt > every);

        if (due) {
            // YOLOX 는 무거워서 관측할 때만 돌린다
            auto o0 = Clock::now();
            std::vector<Candidate> use = cands;
            if (detector.enabled()) {
                auto d0 = Clock::now();
                std::vector<Detection> dets = detector.detect(frame, panel.roi);
                use = detect::merge(std::move(use), q, dets);
                detectMs = msSince(d0);
            }
            // 판 밖에 선 박스는 버린다
            use.erase(std::remove_if(use.begin(), use.end(), [&](const Candidate& c) { return !onPanel(panel, c.box); }), use.end());

            auto e1 = Clock::now();
            truncated = (int)use.size() > cfg.maxCandidates;
            if (truncated) use.resize(cfg.maxCandidates);   // 넓이 큰 순으로 정렬돼 있다

            std::vector<cv::Mat> vecs;
            std::vector<Cached> next;
            lastEncoded = lastReused = 0;
            if (q.valid) {
                for (const auto& c : use) {
                    cv::Mat th = thumbOf(frame, c.box), v;
                    // 재검사 때는 늘 새로 인코딩
                    if (!rescan && !th.empty())
                        for (const auto& k : cache)
                            if (!k.vec.empty() && iou(k.box, c.box) > 0.6 && cv::norm(k.thumb, th, cv::NORM_L1) / th.total() < 8.0) {
                                v = k.vec;
                                ++lastReused;
                                break;
                            }
                    if (v.empty()) { v = encoder->encode(frame, c.box); ++lastEncoded; }
                    vecs.push_back(v);
                    next.push_back({c.box, th, v});
                }
                cache = std::move(next);
            }
            encodeMs = msSince(e1);

            auto sendAt = Clock::now();
            obs::Header h;
            h.deviceId = cfg.deviceId;
            h.bootId = runId;
            h.sequence = ++sequence;
            h.requestId = requestId;
            h.capturedAt = isoUtc(std::chrono::system_clock::now() - (sendAt - capT));
            h.captureMonoNs = monoNs(capT);
            h.frameAgeMs = std::chrono::duration_cast<std::chrono::milliseconds>(sendAt - capT).count();
            h.imageWidth = frame.cols;
            h.imageHeight = frame.rows;
            h.roiVersion = cfg.roiVersion;
            h.frameId = frameSeq;
            h.spaceId = encoder->spaceId();
            h.dim = encoder->dim();
            h.l2 = encoder->l2();
            h.moving = false;
            h.processingMs = msSince(o0);
            const std::string json = obs::json(h, q, use, vecs);

            sh.keep(frameSeq, sh.frameAt(frameSeq));
            {
                std::lock_guard<std::mutex> lk(sh.m);
                sh.latestObs = json;
                if (rescan) { sh.rescanAtNs = 0; sh.rescanRequestId.clear(); }
                auto& v = sh.view;
                v.encodedBoxes.clear();
                for (size_t i = 0; i < vecs.size(); ++i)
                    if (!vecs[i].empty()) v.encodedBoxes.push_back(use[i].box);
                char info[200];
                std::snprintf(info, sizeof info, "%s %dd | obs #%llu | %zu boxes -> features in %lld ms (new %d, reused %d)%s",
                              encoder->spec().name.c_str(), encoder->dim(), (unsigned long long)sequence, v.encodedBoxes.size(),
                              encodeMs, lastEncoded, lastReused, q.valid ? "" : (" | scene invalid: " + q.reason).c_str());
                v.modelInfo = info;
                v.modelAt = sendAt;
            }
            if (mqtt && !mqtt->publish("observation", json, 1, false))
                std::fprintf(stderr, "[mqtt] 연결 안 됨 — 관측 #%llu 은 HTTP·파일로만\n", (unsigned long long)sequence);
            lastObsAt = sendAt;
            if (changed || use.size() != lastBoxes) burst = 3;
            else if (burst > 0) --burst;
            lastBoxes = use.size();
            changed = false;
            std::fprintf(stderr, "[node] 관측 #%llu %s · 박스 %zu%s (새로 %d · 재사용 %d) · 추출 %lld ms · 인코딩 %lld ms · 나이 %lld ms%s\n",
                         (unsigned long long)sequence, q.valid ? "유효" : q.reason.c_str(), use.size(), truncated ? "(잘림)" : "",
                         lastEncoded, lastReused, extractMs + detectMs, encodeMs, (long long)h.frameAgeMs, requestId.empty() ? "" : (" · 요청 " + requestId).c_str());

            if (outOk) {   // 쓰다 만 파일이 보이지 않게 임시 파일 + rename
                std::string tmp = cfg.outDir + "/latest.json.tmp", dst = cfg.outDir + "/latest.json";
                std::ofstream(tmp, std::ios::trunc) << json << "\n";
                fs::rename(tmp, dst, ec);
            }
            if (!cfg.saveDir.empty()) saveSample(cfg, frame, json, sequence);
        }

        // /health 는 1초마다, MQTT health 는 health_sec 마다
        if (Clock::now() - lastHealth >= std::chrono::seconds(1)) {
            lastHealth = Clock::now();
            const char* state = moving ? "moving" : settled ? "stable" : "settling";
            std::ostringstream o;
            o.setf(std::ios::fixed);
            o.precision(1);
            o << "{\"device_id\":" << obs::quote(cfg.deviceId) << ",\"run_id\":" << obs::quote(runId)
              << ",\"state\":\"" << state << "\",\"camera_running\":true,\"fps\":" << fps
              << ",\"uptime_s\":" << std::chrono::duration_cast<std::chrono::seconds>(Clock::now() - startedAt).count()
              << ",\"sequence\":" << sequence << ",\"last_observation_age_s\":"
              << (sequence ? std::chrono::duration<double>(Clock::now() - lastObsAt).count() : -1.0)
              << ",\"scene_valid\":" << (q.valid ? "true" : "false") << ",\"scene_reason\":" << (q.reason.empty() ? "null" : obs::quote(q.reason))
              << ",\"candidates\":" << cands.size() << ",\"truncated\":" << (truncated ? "true" : "false")
              << ",\"extract_ms\":" << extractMs << ",\"detect_ms_last\":" << detectMs << ",\"encode_ms_last\":" << encodeMs << ",\"encoded_last\":" << lastEncoded
              << ",\"reused_last\":" << lastReused << ",\"cpu_temp_c\":" << cpuTempC()
              << ",\"mqtt_connected\":" << (mqtt && mqtt->connected() ? "true" : "false")
              << ",\"board\":" << (warp.empty() ? "false" : "true")
              << ",\"embedding_space_id\":" << obs::quote(encoder->spaceId()) << "}";
            const std::string health = o.str();
            {
                std::lock_guard<std::mutex> lk(sh.m);
                sh.health = health;
            }
            if (mqtt && Clock::now() - lastMqttHealth >= std::chrono::seconds(cfg.healthSec)) {
                lastMqttHealth = Clock::now();
                mqtt->publish("health", health, 0, false);
            }
        }
    }

    std::fprintf(stderr, "[node] 종료\n");
    mqtt.reset();
    http.stop();
    cam.reset();
    return 0;
}
