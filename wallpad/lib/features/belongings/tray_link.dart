import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'observation.dart';
import '../../device/local_mqtt.dart';

/// 트레이 노드와의 MQTT 연결.
///   leaveguard/belongings/<장치>/observation   ← 관측 JSON
///   leaveguard/belongings/<장치>/availability  ← online / offline (LWT)
///   leaveguard/belongings/<장치>/command       → {"cmd":"rescan","request_id":…}
class TrayLink {
  static const _topics = 'leaveguard/belongings/+/';

  MqttServerClient? _client;
  final _observations = StreamController<BelongingObservation>.broadcast();
  final _status = StreamController<void>.broadcast();
  var _nextRequest = 0;

  bool connected = false;
  final online = <String, bool>{};

  Stream<BelongingObservation> get observations => _observations.stream;
  Stream<void> get changes => _status.stream;

  bool get nodeOnline => connected && online.values.any((v) => v);

  Future<void> start() async {
    if (_client != null) return;
    final client = _client = localMqttClient('leaveguard-wallpad', _setConnected);
    await connectWhenUp(client, () => _client != null);
    client.subscribe('${_topics}observation', MqttQos.atLeastOnce);
    client.subscribe('${_topics}availability', MqttQos.atLeastOnce);
    client.updates?.listen(_onMessages);
  }

  void _setConnected(bool v) {
    connected = v;
    _status.add(null);
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage?>> messages) {
    for (final m in messages) {
      final payload = m.payload;
      if (payload is! MqttPublishMessage) continue;
      final text = utf8.decode(payload.payload.message, allowMalformed: true);
      final parts = m.topic.split('/');
      if (parts.length != 4) continue;
      final device = parts[2];
      if (parts[3] == 'availability') {
        online[device] = text.trim() == 'online';
        _status.add(null);
      } else if (parts[3] == 'observation') {
        try {
          final o = BelongingObservation.parse(text);
          online[device] = true;
          _observations.add(o);
        } catch (_) {}
      }
    }
  }

  /// 요청 이후 프레임으로 다시 관측한 결과. 못 받으면 null.
  Future<BelongingObservation?> rescan({String device = 'tray01', Duration timeout = const Duration(seconds: 8)}) async {
    final client = _client;
    if (client == null || !connected) return null;
    final id = 'wallpad-${DateTime.now().millisecondsSinceEpoch}-${_nextRequest++}';
    final reply = observations.firstWhere((o) => o.requestId == id).timeout(timeout);
    final builder = MqttClientPayloadBuilder()..addUTF8String(jsonEncode({'cmd': 'rescan', 'request_id': id}));
    client.publishMessage('leaveguard/belongings/$device/command', MqttQos.atLeastOnce, builder.payload!);
    try {
      return await reply;
    } catch (_) {
      return null;
    }
  }
}
