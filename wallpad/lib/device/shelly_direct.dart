import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Shelly Plug Gen3 HTTP RPC 직접 제어. 전력 노드가 릴레이 상태를 안 주므로 읽기는 늘 하고, 명령은 노드가 없을 때의 예비다.
class ShellyDirect {
  ShellyDirect(this.plugs);

  final Map<String, String> plugs;

  final output = <String, bool>{};
  final amps = <String, double>{};
  final _at = <String, DateTime>{};

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  Timer? _timer;

  static const stale = Duration(seconds: 5);

  bool fresh(String id) {
    final t = _at[id];
    return t != null && DateTime.now().difference(t) < stale;
  }

  bool has(String id) => plugs.containsKey(id);

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_polling) _pollAll();
    });
    _pollAll();
  }

  // 플러그가 응답하지 않으면 한 번에 몇 초씩 걸려서, 이전 조회가 끝나기 전엔 새로 시작하지 않는다
  var _polling = false;

  Future<void> _pollAll() async {
    _polling = true;
    try {
      await _pollEach();
    } finally {
      _polling = false;
    }
  }

  Future<void> _pollEach() async {
    for (final id in plugs.keys) {
      final j = await _get(id, 'Switch.GetStatus?id=0');
      if (j == null) continue;
      final out = j['output'] == true;
      final a = (j['current'] as num?)?.toDouble() ?? 0;
      final changed = output[id] != out || ((amps[id] ?? -1) - a).abs() >= 0.02 || !fresh(id);
      output[id] = out;
      amps[id] = a;
      _at[id] = DateTime.now();
      if (changed) _changes.add(null);
    }
  }

  Future<bool> set(String id, {required bool on}) async {
    final j = await _get(id, 'Switch.Set?id=0&on=$on');
    if (j == null) return false;
    await _pollAll();
    return output[id] == on;
  }

  Future<Map<String, dynamic>?> _get(String id, String path) async {
    final ip = plugs[id];
    if (ip == null) return null;
    try {
      final req = await _http.getUrl(Uri.parse('http://$ip/rpc/$path')).timeout(const Duration(seconds: 2));
      final res = await req.close().timeout(const Duration(seconds: 2));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 2));
      final j = jsonDecode(body);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }
}
