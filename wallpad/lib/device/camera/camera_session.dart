import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/config/scan_config.dart';
import 'preview_frames.dart';
import '../../app/backend.dart';
import 'vision.dart';

/// 카메라 화면 공통: vision 세션 열고 닫기, 미리보기 프레임, 정리. 보드가 아니면 열지 않는다.
mixin CameraSession<T extends StatefulWidget> on State<T> {
  final _frames = PreviewFrames();
  VisionSession? _session;

  ui.Image? get frame => _session == null ? null : _frames.image;

  bool get watching => _session != null;

  VisionSession? get session => _session;

  /// frame·error 를 뺀 응답.
  void onVision(VisionEvent event);

  void cameraFailed();

  /// [mode] 는 preview | scan
  Future<void> openCamera(String mode) async {
    closeCamera(); // 안 닫으면 이전 세션 응답이 섞인다
    if (!onBoard) return;
    try {
      await vision.start();
    } catch (_) {
      return _failed();
    }
    if (!mounted) return;
    _session = mode == 'preview'
        ? vision.preview(_onEvent, camera: CameraConfig.face)
        : vision.scan(_onEvent, camera: CameraConfig.face);
  }

  void closeCamera() {
    _session?.stop();
    _session = null;
  }

  @override
  void dispose() {
    closeCamera();
    _frames.dispose();
    super.dispose();
  }

  void _onEvent(VisionEvent event) {
    switch (event.type) {
      case 'frame':
        _frames.update(event.args).then((changed) {
          if (changed && mounted) setState(() {});
        });
      case 'error':
        _failed();
      default:
        onVision(event);
    }
  }

  void _failed() {
    closeCamera();
    if (mounted) cameraFailed();
  }
}
