import 'package:mqtt_client/mqtt_server_client.dart';

/// 앱이 띄운 로컬 브로커에 붙는 자동 재연결 클라이언트.
MqttServerClient localMqttClient(String clientId, void Function(bool connected) onConnection) {
  final client = MqttServerClient('127.0.0.1', clientId)
    ..port = 1883
    ..keepAlivePeriod = 20
    ..autoReconnect = true
    ..resubscribeOnAutoReconnect = true
    ..logging(on: false);
  client.onConnected = () => onConnection(true);
  client.onAutoReconnected = () => onConnection(true);
  client.onDisconnected = () => onConnection(false);
  client.onAutoReconnect = () => onConnection(false);
  return client;
}

/// 브로커가 아직 안 떴을 수 있어 붙을 때까지 재시도한다. [alive] 가 false 면 멈춘다.
Future<void> connectWhenUp(MqttServerClient client, bool Function() alive) async {
  for (var i = 0; alive(); i++) {
    try {
      await client.connect();
      return;
    } catch (_) {
      await Future<void>.delayed(Duration(seconds: i < 5 ? 2 : 10));
    }
  }
}
