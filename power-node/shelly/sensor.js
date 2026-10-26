// Shelly Plug M Gen3 내부 스크립트 (웹 UI → Scripts에 붙여넣고 Run, "Run on startup" 켜기)
// TOPIC은 플러그마다 다르다: 고데기 shelly/iron/sensor, 드라이기 shelly/dryer/sensor
// 1초마다 전류(A)를 숫자 텍스트(예: "0.073")로 발행한다. 멈추면 powernode가 10초 뒤 UNKNOWN으로 바꾼다.

let TOPIC = "shelly/iron/sensor";

Timer.set(1000, true, function () {
  if (!MQTT.isConnected()) return;
  let s = Shelly.getComponentStatus("switch", 0);
  MQTT.publish(TOPIC, JSON.stringify(s.current), 0, false);
});
+- 