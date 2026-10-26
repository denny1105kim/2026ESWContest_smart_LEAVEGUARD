#pragma once
// YuNet detection -> 5-point alignment -> SFace feature, MiniFASNet liveness (door camera only).
#include <algorithm>
#include <cmath>
#include <string>
#include <vector>
#include <opencv2/core.hpp>
#include <opencv2/dnn.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/objdetect/face.hpp>

// 도 단위. yaw > 0 = 본인 기준 왼쪽, pitch > 0 = 위
struct HeadPose {
    float yaw = 0, pitch = 0;
    bool ok = false;
};

class Face {
public:
    // 임베딩과 함께 저장된다. 버전이 다르면 비교하지 않는다
    static constexpr const char* VERSION = "face_recognition_sface_2021dec";
    static constexpr int MIN_FACE = 60;   // 얼굴 폭 px (640x480 기준)

    // 조회용 프레임 품질 기준
    static constexpr float MAX_YAW   = 0.28f;   // 코가 두 눈 가운데에서 벗어난 정도 / 눈 사이 거리
    static constexpr double MIN_SHARP = 40.0;   // 라플라시안 분산
    static constexpr double MIN_LIGHT = 45.0;   // 얼굴 평균 밝기 (0~255)
    static constexpr double MAX_LIGHT = 225.0;

    explicit Face(const std::string& dir) {
        det = cv::FaceDetectorYN::create(dir + "/face-detection/face_detection_yunet_2023mar.onnx", "", cv::Size(320, 240), 0.6f, 0.3f, 5000);
        rec = cv::FaceRecognizerSF::create(dir + "/face-recognition/" + VERSION + ".onnx", "");
        spoof[0] = cv::dnn::readNetFromONNX(dir + "/anti-spoofing/anti_spoofing_minifasnetv2_2.7_80x80.onnx");
        spoof[1] = cv::dnn::readNetFromONNX(dir + "/anti-spoofing/anti_spoofing_minifasnetv1se_4.0_80x80.onnx");
    }

    // 두 모델 softmax 의 real(1번) 평균. 입력은 80x80 BGR 0~255 (정규화 안 함)
    float liveness(const cv::Mat& img, const cv::Mat& row) {
        static const float scales[2] = {2.7f, 4.0f};
        float real = 0;
        for (int i = 0; i < 2; ++i) {
            cv::Mat crop; cv::resize(img(widen(img, row, scales[i])), crop, cv::Size(80, 80));
            spoof[i].setInput(cv::dnn::blobFromImage(crop, 1.0, cv::Size(80, 80), cv::Scalar(), /*swapRB=*/false));
            cv::Mat logits = spoof[i].forward().reshape(1, 1);
            double mx; cv::minMaxLoc(logits, nullptr, &mx);
            cv::Mat e; cv::exp(logits - mx, e);
            real += (float)(e.at<float>(0, 1) / cv::sum(e)[0]);
        }
        return real / 2;
    }

    // YuNet 한 행: 박스 4 + 랜드마크 10 + 점수
    std::vector<cv::Mat> detect(const cv::Mat& img) {
        // 절반 크기로 검출하고 좌표를 2배로 되돌린다
        cv::Mat half; cv::resize(img, half, cv::Size(img.cols / 2, img.rows / 2));
        det->setInputSize(half.size());
        cv::Mat faces; det->detect(half, faces);

        std::vector<cv::Mat> out;
        for (int i = 0; i < faces.rows; ++i) {
            cv::Mat row = faces.row(i).clone();
            row.colRange(0, 14) *= 2.0f;
            if (row.at<float>(0, 2) >= MIN_FACE) out.push_back(row);
        }
        return out;
    }

    static bool usable(const cv::Mat& img, const cv::Mat& row) {
        cv::Point2f eyeL(row.at<float>(0, 4), row.at<float>(0, 5));
        cv::Point2f eyeR(row.at<float>(0, 6), row.at<float>(0, 7));
        cv::Point2f nose(row.at<float>(0, 8), row.at<float>(0, 9));
        float between = (float)cv::norm(eyeR - eyeL);
        if (between < 1) return false;
        if (std::abs(nose.x - (eyeL.x + eyeR.x) / 2) / between > MAX_YAW) return false;
        return sharpAndLit(img, row);
    }

    // 크기·밝기·선명도만 본다 (방향은 보지 않음)
    static bool sharpAndLit(const cv::Mat& img, const cv::Mat& row) {
        cv::Rect box(cvRound(row.at<float>(0, 0)), cvRound(row.at<float>(0, 1)),
                     cvRound(row.at<float>(0, 2)), cvRound(row.at<float>(0, 3)));
        box &= cv::Rect({}, img.size());
        if (box.width < MIN_FACE) return false;

        cv::Mat gray, sharp;
        cv::cvtColor(img(box), gray, cv::COLOR_BGR2GRAY);
        double light = cv::mean(gray)[0];
        if (light < MIN_LIGHT || light > MAX_LIGHT) return false;

        cv::Laplacian(gray, sharp, CV_64F);
        cv::Scalar mu, sigma;
        cv::meanStdDev(sharp, mu, sigma);
        return sigma[0] * sigma[0] >= MIN_SHARP;
    }

    // 5점으로 어림한다 (solvePnP 는 5점에서 거울상 해가 섞인다).
    //   yaw: 코끝이 눈보다 눈 사이 거리의 0.44배 앞에 있다고 보고 atan(코 비켜남 / 0.44)
    //   pitch: 눈~입 사이 코 높이가 정면에서 약 0.55
    static HeadPose pose(const cv::Mat& /*img*/, const cv::Mat& row) {
        cv::Point2f eyeA(row.at<float>(0, 4), row.at<float>(0, 5)), eyeB(row.at<float>(0, 6), row.at<float>(0, 7));
        cv::Point2f nose(row.at<float>(0, 8), row.at<float>(0, 9));
        cv::Point2f mouthA(row.at<float>(0, 10), row.at<float>(0, 11)), mouthB(row.at<float>(0, 12), row.at<float>(0, 13));
        cv::Point2f eyes = (eyeA + eyeB) * 0.5f, mouth = (mouthA + mouthB) * 0.5f;
        float between = (float)cv::norm(eyeB - eyeA);
        float height = mouth.y - eyes.y;
        HeadPose p;
        if (between < 1 || height < 1) return p;
        p.yaw = (float)(std::atan((nose.x - eyes.x) / between / 0.44) * 180 / CV_PI);
        p.pitch = (0.55f - (nose.y - eyes.y) / height) * 100;
        p.ok = std::isfinite(p.yaw) && std::isfinite(p.pitch);
        return p;
    }

    // Silent-Face CropImage._get_new_box 와 같은 확장 박스, 그림 안으로 민다
    static cv::Rect widen(const cv::Mat& img, const cv::Mat& row, float scale) {
        float x = row.at<float>(0, 0), y = row.at<float>(0, 1), w = row.at<float>(0, 2), h = row.at<float>(0, 3);
        scale = std::min({(img.rows - 1.f) / h, (img.cols - 1.f) / w, scale});
        float nw = w * scale, nh = h * scale;
        float cx = x + w / 2, cy = y + h / 2;
        float l = std::max(0.f, cx - nw / 2), t = std::max(0.f, cy - nh / 2);
        if (l + nw > img.cols - 1) l = img.cols - 1 - nw;
        if (t + nh > img.rows - 1) t = img.rows - 1 - nh;
        return cv::Rect(cvRound(l), cvRound(t), cvRound(nw), cvRound(nh)) & cv::Rect({}, img.size());
    }

    cv::Mat feature(const cv::Mat& img, const cv::Mat& row) {
        cv::Mat aligned, f;
        rec->alignCrop(img, row, aligned);
        rec->feature(aligned, f);
        return f;
    }

private:
    cv::Ptr<cv::FaceDetectorYN>   det;
    cv::Ptr<cv::FaceRecognizerSF> rec;
    cv::dnn::Net                  spoof[2];
};
