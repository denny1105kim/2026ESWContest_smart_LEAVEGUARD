import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

/// vision 의 BGRA 미리보기 파일을 그림으로 바꾼다. 디코딩 중에 온 장은 건너뛴다.
class PreviewFrames {
  ui.Image? image;
  var _busy = false;

  /// `frame <w> <h> <경로>` 인자. 그림이 바뀌면 true.
  Future<bool> update(List<String> args) async {
    if (_busy) return false;
    _busy = true;
    try {
      final pixels = await File(args[2]).readAsBytes();
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          pixels, int.parse(args[0]), int.parse(args[1]), ui.PixelFormat.bgra8888, done.complete);
      // 먼저 dispose 하면 그 사이 다시 그릴 때 "Cannot clone a disposed image" 가 난다
      final old = image;
      image = await done.future;
      old?.dispose();
      return true;
    } catch (_) {
      return false; // vision 이 파일을 바꾸는 순간일 수 있다
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    image?.dispose();
    image = null;
  }
}
