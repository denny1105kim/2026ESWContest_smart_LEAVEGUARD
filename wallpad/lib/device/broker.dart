import 'dart:async';
import 'dart:io';

/// 앱 번들의 mosquitto 를 띄우고 죽으면 다시 띄운다 (Atlas 는 /etc 가 읽기 전용이라 systemd 를 못 쓴다).
class Broker {
  Process? _process;
  Timer? _retry;
  var _failures = 0;
  var _stopped = false;

  bool get running => _process != null;

  Future<void> start() async {
    _stopped = false;
    if (_process != null) return;
    final dir = '${File(Platform.resolvedExecutable).parent.path}/broker';
    try {
      final process = _process = await Process.start('$dir/mosquitto', ['-c', '$dir/mosquitto.conf'], workingDirectory: dir);
      process.stdin.close().ignore();

      final cache = Platform.environment['XDG_CACHE_HOME'] ?? '/tmp';
      final log = File('$cache/leaveguard_broker.log').openWrite(mode: FileMode.append);
      process.stdout.listen(log.add);
      process.stderr.listen(log.add);
      final started = DateTime.now();
      process.exitCode.then((code) {
        log.close().ignore();
        _process = null;
        // 금방 죽으면 재시도 간격을 늘린다
        _failures = DateTime.now().difference(started) < const Duration(seconds: 10) ? _failures + 1 : 0;
        _scheduleRestart();
      });
    } catch (_) {
      _process = null;
      _failures++;
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    if (_stopped) return;
    _retry?.cancel();
    final wait = Duration(seconds: (2 << _failures.clamp(0, 5)).clamp(2, 60));
    _retry = Timer(wait, start);
  }

  void stop() {
    _stopped = true;
    _retry?.cancel();
    _process?.kill();
  }
}
