class ScanConfig {
  /// 같은 사람으로 확인돼야 하는 서로 다른 프레임 수
  static const confirmFrames = 2;

  /// SFace 코사인 유사도 기준 (OpenCV 권장값). 모델을 바꾸면 다시 정한다
  static const threshold = 0.363;

  /// 1등과 2등의 차이가 이만큼은 나야 확정한다. 가족은 서로 닮았다
  static const margin = 0.1;
}

/// 카메라 모델 이름의 일부 (대소문자 무시). 못 찾으면 첫 번째 카메라를 쓴다
class CameraConfig {
  static const face = 'LifeCam';
}

class DoorCamConfig {
  /// 카메라 펌웨어 DEVICE_ID. MQTT 토픽과 X-Device-Id 헤더에 쓰인다
  static const device = 'cam1';

  /// ESP32-CAM 화질로는 본인도 LifeCam 기준보다 낮게 나와서 따로 둔다
  static const threshold = 0.30;
}

class TrayNodeConfig {
  static const url = 'http://192.168.0.51:8080';
}
