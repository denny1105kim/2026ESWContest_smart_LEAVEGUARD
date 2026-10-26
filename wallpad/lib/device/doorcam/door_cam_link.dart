import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../../core/config/scan_config.dart';
import '../local_mqtt.dart';

/// 현관 카메라(ESP32-CAM)와의 MQTT 연결.
///   leaveguard/esp32cam/<장치>/face          → detected | known | unknown | idle
///   leaveguard/esp32cam/<장치>/state         ← idle | detected | known | unknown (retained)
///   leaveguard/esp32cam/<장치>/availability  ← online / offline (LWT)
///   leaveguard/door/lock/set                 → UNLOCK
/// 명령은 retain 하지 않는다. 재접속 때 옛 명령이 다시 실행된다.
class DoorCamLink {
  MqttServerClient? _client;
  final _changes = StreamController<void>.broadcast();

  bool connected = false;
  final online = <String, bool>{};
  final state = <String, String>{};

  Stream<void> get changes => _changes.stream;

  Future<void> start() async {
    if (_client != null) return;
    final client = _client = localMqttClient('leaveguard-wallpad-doorcam', _setConnected);
    await connectWhenUp(client, () => _client != null);
    client.subscribe('leaveguard/esp32cam/+/state', MqttQos.atLeastOnce);
    client.subscribe('leaveguard/esp32cam/+/availability', MqttQos.atLeastOnce);
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
      if (parts.length != 4 || parts[1] != 'esp32cam') continue;
      if (parts[3] == 'availability') {
        online[parts[2]] = text == 'online';
      } else if (parts[3] == 'state') {
        state[parts[2]] = text;
      } else {
        continue;
      }
      _changes.add(null);
    }
  }

  // detected 면 카메라가 12fps, idle 이면 3fps 로 바뀐다
  void face(String command, {String device = DoorCamConfig.device}) => _publish('leaveguard/esp32cam/$device/face', command);

  void openDoor() => _publish('leaveguard/door/lock/set', 'UNLOCK');

  void _publish(String topic, String text) {
    final client = _client;
    if (client == null || !connected) return;
    final builder = MqttClientPayloadBuilder()..addString(text);
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void stop() {
    _client?.disconnect();
    _client = null;
  }
}
