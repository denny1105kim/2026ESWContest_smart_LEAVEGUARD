#pragma once
// 관측 메시지 (JSON, schema 2). 특징 벡터는 float32 리틀엔디언을 base64 로 싣는다.
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>
#include <opencv2/core.hpp>
#include "PanelExtractor.h"

namespace obs {

inline std::string base64(const unsigned char* data, size_t n) {
    static const char* t = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    out.reserve((n + 2) / 3 * 4);
    for (size_t i = 0; i < n; i += 3) {
        uint32_t v = data[i] << 16 | (i + 1 < n ? data[i + 1] << 8 : 0) | (i + 2 < n ? data[i + 2] : 0);
        out += t[v >> 18 & 63];
        out += t[v >> 12 & 63];
        out += i + 1 < n ? t[v >> 6 & 63] : '=';
        out += i + 2 < n ? t[v & 63] : '=';
    }
    return out;
}

// ARM·x86 모두 리틀엔디언이라 메모리를 그대로 싣는다
inline std::string vector64(const cv::Mat& v) {
    CV_Assert(v.type() == CV_32F && v.isContinuous());
    return base64(v.ptr<unsigned char>(), v.total() * sizeof(float));
}

inline std::string quote(const std::string& s) {
    std::string out = "\"";
    for (char c : s) {
        if (c == '"' || c == '\\') out += '\\';
        out += c;
    }
    return out + "\"";
}

struct Header {
    std::string deviceId;
    std::string bootId;
    uint64_t sequence = 0;
    std::string requestId;           // rescan 응답이면 그 ID
    std::string capturedAt;          // UTC ISO-8601, 참고용
    int64_t captureMonoNs = 0;       // 이 장치의 단조 시계, 다른 장치와 비교하지 않는다
    int64_t frameAgeMs = 0;
    int imageWidth = 0, imageHeight = 0;
    std::string roiVersion;
    uint64_t frameId = 0;            // /snapshot.jpg · /crop.jpg · /encode 의 frame_id
    std::string spaceId;             // Encoder::spaceId()
    int dim = 0;
    bool l2 = true;
    bool moving = false;
    int64_t processingMs = 0;
};

inline std::string observationId(const Header& h) { return h.deviceId + "/" + h.bootId + "/" + std::to_string(h.sequence); }

inline std::string json(const Header& h, const SceneQuality& q, const std::vector<Candidate>& cands,
                        const std::vector<cv::Mat>& vecs) {
    std::ostringstream o;
    o.setf(std::ios::fixed);
    o.precision(4);
    o << "{\"schema_version\":2"
      << ",\"device_id\":" << quote(h.deviceId) << ",\"boot_id\":" << quote(h.bootId) << ",\"sequence\":" << h.sequence
      << ",\"observation_id\":" << quote(observationId(h))
      << ",\"request_id\":" << (h.requestId.empty() ? "null" : quote(h.requestId))
      << ",\"captured_at\":" << quote(h.capturedAt) << ",\"capture_monotonic_ns\":" << h.captureMonoNs
      << ",\"frame_age_ms_at_send\":" << h.frameAgeMs
      << ",\"image_width\":" << h.imageWidth << ",\"image_height\":" << h.imageHeight
      << ",\"frame_id\":" << h.frameId << ",\"roi_version\":" << quote(h.roiVersion)
      << ",\"embedding_space_id\":" << quote(h.spaceId) << ",\"embedding_dim\":" << h.dim << ",\"dtype\":\"f32le\""
      << ",\"l2_normalized\":" << (h.l2 ? "true" : "false")
      << ",\"processing_ms\":" << h.processingMs
      << ",\"scene_quality\":{\"valid\":" << (q.valid ? "true" : "false")
      << ",\"reason\":" << (q.reason.empty() ? "null" : quote(q.reason))
      << ",\"moving\":" << (h.moving ? "true" : "false")
      << ",\"band_inliers\":" << q.bandInliers << ",\"light_mad\":" << q.lightMad << ",\"chroma_mad\":" << q.chromaMad
      << ",\"plane_tilt\":" << q.planeTilt << ",\"foreground\":" << q.foreground << ",\"mean_light\":" << q.meanLight << "}"
      << ",\"candidates\":[";
    for (size_t i = 0; i < cands.size(); ++i) {
        const auto& c = cands[i];
        if (i) o << ",";
        o << "{\"id\":" << i << ",\"bbox\":[" << c.box.x << "," << c.box.y << "," << c.box.width << "," << c.box.height << "]"
          << ",\"contrast\":" << c.contrast << ",\"fill\":" << c.fill << ",\"parts\":" << c.parts << ",\"source\":" << quote(c.source)
          << ",\"embedding\":" << (i < vecs.size() && !vecs[i].empty() ? quote(vector64(vecs[i])) : "null") << "}";
    }
    o << "]}";
    return o.str();
}

}  // namespace obs
