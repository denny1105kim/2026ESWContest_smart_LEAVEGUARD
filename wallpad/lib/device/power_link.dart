import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'local_mqtt.dart';

/// 전력 노드와의 MQTT 연결.
///   leaveguard/power/<가전>/state       ← UNKNOWN / IDLE / IN_USE (retained)
///   leaveguard/power/<가전>/set         → ON / OFF (retain 금지)
///   leaveguard/power/node/availability  ← online / offline
///   shelly/<가전>/sensor                ← 전류(A), 1초마다
class PowerLink {
  // powernode 와 같은 켜짐 기준
  static const onAmps = 0.08;

  // powernode STALE_SEC 와 같다
  static const stale = Duration(seconds: 10);

  MqttServerClient? _client;
  final _changes = StreamController<void>.broadcast();
  Timer? _tick;

  bool connected = false;
  bool nodeOnline = false;
  final state = <String, String>{};
  final amps = <String, double>{};
  final _sampledAt = <String, DateTime>{};

  Stream<void> get changes => _changes.stream;

  bool known(String device) {
    final t = _sampledAt[device];
    return connected && nodeOnline && t != null && DateTime.now().difference(t) < stale && state[device] != 'UNKNOWN';
  }

  bool inUse(String device) => known(device) && state[device] == 'IN_USE';

  // 전류값이 끊겨도 노드는 플러그에 명령을 전한다
  bool get nodeUp => connected && nodeOnline;

  Future<void> start() async {
    if (_client != null) return;
    final client = _client = localMqttClient('leaveguard-wallpad-power', _setConnected);
    // 메시지가 끊겨도 stale 을 알아채도록 주기적으로 알린다
    _tick = Timer.periodic(const Duration(seconds: 3), (_) => _changes.add(null));
    await connectWhenUp(client, () => _client != null);
    client.subscribe('leaveguard/power/+/state', MqttQos.atLeastOnce);
    client.subscribe('leaveguard/power/node/availability', MqttQos.atLeastOnce);
    client.subscribe('shelly/+/sensor', MqttQos.atMostOnce);
    client.updates?.listen(_onMessages);
  }

  void _setConnected(bool v) {
    connected = v;
    _changes.add(null);
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage?>> messages) {
    for (final m in messages) {
      final payload = m.payload;
      if (payload is! MqttPublishMessage) continue;
      final text = utf8.decode(payload.payload.message, allowMalformed: true).trim();
      final parts = m.topic.split('/');
      if (parts.length == 4 && parts[1] == 'power' && parts[2] == 'node' && parts[3] == 'availability') {
        nodeOnline = text == 'online';
      } else if (parts.length == 4 && parts[1] == 'power' && parts[3] == 'state') {
        state[parts[2]] = text;
      } else if (parts.length == 3 && parts[0] == 'shelly' && parts[2] == 'sensor') {
        final a = double.tryParse(text);
        if (a == null) continue;
        amps[parts[1]] = a;
        _sampledAt[parts[1]] = DateTime.now();
      } else {
        continue;
      }
      _changes.add(null);
    }
  }

  /// 끌 때는 [timeout] 안에 전류가 [onAmps] 아래로 떨어져야 성공이다.
  Future<bool> set(String device, {required bool on, Duration timeout = const Duration(seconds: 8)}) async {
    final client = _client;
    if (client == null || !connected) return false;
    final builder = MqttClientPayloadBuilder()..addString(on ? 'ON' : 'OFF');
    client.publishMessage('leaveguard/power/$device/set', MqttQos.atLeastOnce, builder.payload!);
    if (on) return true;
    // 명령 뒤에 새로 온 전류값으로만 판단한다
    final sent = DateTime.now();
    bool off() => (_sampledAt[device]?.isAfter(sent) ?? false) && amps[device]! < onAmps;
    try {
      await changes.firstWhere((_) => off()).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  void stop() {
    _tick?.cancel();
    _client?.disconnect();
    _client = null;
  }
}
