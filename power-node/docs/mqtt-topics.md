# MQTT 토픽 규약 (전력)

모든 노드는 Pi5의 브로커 하나에 접속한다 (포트 1883, 현재 익명 접속).

토픽 형식: `leaveguard/{영역}/{장치}/{종류}`

- `종류`가 보내는 쪽을 정한다. `state`는 전력 노드만, `set`은 월패드만 보낸다.
- 보낸 사람 이름은 토픽에 넣지 않는다. 막아야 하면 브로커 ACL로 막는다.

## 월패드가 쓰는 토픽

| 토픽 | 방향 | 값 | QoS | retain |
|---|---|---|---|---|
| `leaveguard/power/iron/state` | 전력노드 → 월패드 | `UNKNOWN` / `IDLE` / `IN_USE` | 1 | O |
| `leaveguard/power/iron/set` | 월패드 → 전력노드 | `ON` / `OFF` | 1 | X |
| `leaveguard/power/dryer/state` | 전력노드 → 월패드 | `UNKNOWN` / `IDLE` / `IN_USE` | 1 | O |
| `leaveguard/power/dryer/set` | 월패드 → 전력노드 | `ON` / `OFF` | 1 | X |
| `leaveguard/power/node/availability` | 전력노드 → 월패드 | `online` / `offline` | 1 | O |

### 값의 뜻

| 토픽 | 값 | 뜻 |
|---|---|---|
| `…/iron/state`, `…/dryer/state` | `IDLE` | 전류 0.08A 미만이 10초 이상 |
| | `IN_USE` | 전류 0.08A 이상이 3초 이상 → 외출 시 경고 대상 |
| | `UNKNOWN` | 전력노드가 막 켜졌거나, Shelly 전류값이 10초 이상 안 옴. "꺼짐"이 아니라 "확인 불가"로 다룬다 |
| `…/node/availability` | `online` | 전력노드가 브로커에 접속해 있음 |
| | `offline` | 전력노드가 꺼졌거나 연결이 끊김. 이때 `state` 값은 믿으면 안 된다 |

### 월패드 구현 참고

- `state`와 `availability`는 retain이라, 월패드가 나중에 켜져도 구독하자마자 현재 값을 받는다.
- 상태는 바뀔 때만 온다. 계속 같은 상태면 메시지가 안 오는 게 정상이다.
- `offline`은 전력노드가 정상 종료하면 바로, 갑자기 끊기면 브로커가 약 15초 뒤에 대신 보낸다 (keepalive 10초 × 1.5).
- `set`을 보낸 뒤 화면을 바로 바꾸지 말고 `state`가 실제로 바뀌는 걸 보고 바꾸는 게 안전하다.
- `set`에 retain을 켜면 안 된다. 기기가 재접속할 때마다 옛 명령이 다시 실행된다.

## 전력노드 ↔ Shelly Plug (내부용)

월패드는 이 토픽을 몰라도 된다. 전력노드가 번역한다.

| 토픽 | 방향 | 값 | QoS |
|---|---|---|---|
| `shelly/iron/sensor` | 고데기 Shelly → 전력노드 | 전류(A) 텍스트, 예: `0.073` (1초마다) | 0 |
| `shelly/dryer/sensor` | 드라이기 Shelly → 전력노드 | 〃 | 0 |
| `shellyplugmg3-70af09f8bbb4/command/switch:0` | 전력노드 → 고데기 Shelly | `on` / `off` | 1 |
| `shellyplugmg3-083af2d0c7a8/command/switch:0` | 전력노드 → 드라이기 Shelly | `on` / `off` | 1 |

`shelly/+/sensor`는 Shelly 기본 기능이 아니라 플러그 안에서 도는 스크립트([shelly/sensor.js](../shelly/sensor.js))가 보낸다. Shelly는 원래 값이 바뀔 때만 보내서, 1초마다 오는 걸 전제로 한 판단 규칙(연속 횟수, `STALE_SEC`)이 맞지 않기 때문이다.

| 월패드 명령 | Shelly 명령 |
|---|---|
| `leaveguard/power/iron/set` `ON` / `OFF` | `shellyplugmg3-70af09f8bbb4/command/switch:0` `on` / `off` |
| `leaveguard/power/dryer/set` `ON` / `OFF` | `shellyplugmg3-083af2d0c7a8/command/switch:0` `on` / `off` |

## 확인 명령

브로커에 접속할 수 있는 기기에서 (`mosquitto-clients` 필요):

```bash
mosquitto_sub -h <Pi5IP> -t 'leaveguard/#' -v                  # 전체 보기
mosquitto_pub -h <Pi5IP> -t leaveguard/power/iron/set -m OFF   # 월패드 대신 명령
```
