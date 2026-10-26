import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'camera_permission.dart';

/// vision 응답 한 줄: `<세션> <종류> [값…]`
class VisionEvent {
  final int session;
  final String type; // started | frame | face | pose | poor | none | many | outside | seen | bad | error
  final List<String> args;

  const VisionEvent(this.session, this.type, this.args);

  List<double> get embedding => args.first.split(',').map(double.parse).toList();

  // + = 미리보기 화면에서 왼쪽
  double get yaw => double.parse(type == 'pose' ? args[0] : args[1]);

  double get pitch => double.parse(type == 'pose' ? args[1] : args[2]);

  // door 세션의 face 에만 있다
  double? get liveness => type == 'face' && args.length > 3 ? double.parse(args[3]) : null;

  bool get steady => type == 'pose' && args.length > 2 && args[2] == '1';

  // 0~1, [faceRotation] 만큼 돌린 프레임 기준
  Rect get faceBox => Rect.fromLTWH(double.parse(args[1]), double.parse(args[2]), double.parse(args[3]), double.parse(args[4]));

  // 얼굴이 바로 서도록 시계 방향으로 돌린 각도 (0 · 90 · 180 · 270)
  int get faceRotation => args.length > 5 ? int.parse(args[5]) : 0;
}

/// 앱 번들 vision/ 프로그램과 stdin/stdout 으로 한 줄씩 주고받는다.
class Vision {
  Process? _process;
  Completer<String>? _ready;
  final _events = StreamController<VisionEvent>.broadcast();
  var _lastSession = 0;

  // 프로그램이 죽으면 모두에게 error 를 알린다
  final _openSessions = <int>{};

  /// 모델이 올라오면 모델 버전을 돌려준다.
  Future<String> start() {
    final ready = _ready;
    if (ready != null) return ready.future;
    final created = _ready = Completer<String>();
    _launch(created);
    return created.future;
  }

  Future<void> _launch(Completer<String> ready) async {
    try {
      if (!await ensureCameraPermissions()) throw StateError('카메라 권한이 없습니다');

      final dir = '${File(Platform.resolvedExecutable).parent.path}/vision';
      // 보드 카메라 라이브러리가 default.profraw 를 남기는 걸 막는다
      final process = _process = await Process.start('$dir/leaveguard_vision', [],
          workingDirectory: dir, environment: {'LLVM_PROFILE_FILE': '/dev/null'});
      process.stdin.done.ignore();

      final cache = Platform.environment['XDG_CACHE_HOME'] ?? '/tmp';
      process.stderr.pipe(File('$cache/leaveguard_vision.log').openWrite()).ignore();

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _onLine(line, ready), onDone: () => _onExit(ready));
    } catch (_) {
      _onExit(ready);
    }
  }

  void _onLine(String line, Completer<String> ready) {
    final parts = line.split(' ');
    if (parts[0] == 'ready') {
      if (!ready.isCompleted) ready.complete(parts[1]);
    } else if (parts.length >= 2) {
      _events.add(VisionEvent(int.parse(parts[0]), parts[1], parts.sublist(2)));
    }
  }

  // 다음 start() 때 다시 띄운다
  void _onExit(Completer<String> ready) {
    if (!ready.isCompleted) ready.completeError(StateError('vision 프로그램이 시작되지 않았습니다'));
    _process = null;
    _ready = null;
    for (final id in {_lastSession, ..._openSessions}) {
      _events.add(VisionEvent(id, 'error', const ['camera']));
    }
    _openSessions.clear();
  }

  VisionSession preview(void Function(VisionEvent) onEvent, {String? camera}) => _open('preview', onEvent, camera);

  VisionSession scan(void Function(VisionEvent) onEvent, {String? camera}) => _open('scan', onEvent, camera);

  /// 현관 카메라 JPEG 를 [VisionSession.jpeg] 로 한 장씩 판정한다.
  VisionSession door(void Function(VisionEvent) onEvent, {bool recognize = false}) => _open('door', onEvent, recognize ? '1' : '0');

  // arg: preview·scan 은 카메라 모델 이름 일부, door 는 0|1
  VisionSession _open(String command, void Function(VisionEvent) onEvent, String? arg) {
    final id = ++_lastSession;
    _openSessions.add(id);
    final subscription = _events.stream.where((e) => e.session == id).listen(onEvent);
    _send(arg == null ? '$command $id' : '$command $id $arg');
    return VisionSession._(this, id, subscription);
  }

  void _send(String line) => _process?.stdin.writeln(line);
}

class VisionSession {
  final Vision _vision;
  final int _id;
  final StreamSubscription<VisionEvent> _subscription;

  VisionSession._(this._vision, this._id, this._subscription);

  /// [guide] 는 미리보기 기준 0~1.
  void snap(Rect guide) {
    final r = [guide.left, guide.top, guide.right, guide.bottom].map((v) => v.toStringAsFixed(3)).join(' ');
    _vision._send('snap $_id $r');
  }

  void track(Rect guide) {
    final r = [guide.left, guide.top, guide.right, guide.bottom].map((v) => v.toStringAsFixed(3)).join(' ');
    _vision._send('track $_id $r');
  }

  // 답(seen | none | bad)이 오기 전에 다음 장을 보내지 않는다
  void jpeg(String path) => _vision._send('jpeg $_id $path');

  void recognize(bool on) => _vision._send('door $_id ${on ? 1 : 0}');

  void stop() {
    _subscription.cancel();
    _vision._openSessions.remove(_id);
    _vision._send('stop $_id');
  }
}
