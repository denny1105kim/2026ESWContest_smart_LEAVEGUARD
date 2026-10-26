const screenW = 1024.0;
const screenH = 600.0;

/// OS 가 화면 맨 아래 약 50px 에서 시작한 터치를 앱 닫기 스와이프로 본다. 바닥에 붙는 것은 이만큼 띄운다
const legacyBottomGap = 64.0;

/// 넘기면 사용자 선택 화면으로
const identifyTimeout = Duration(seconds: 10);

/// 인식에 성공하면 이름을 보여 주는 시간
const nameFlash = Duration(milliseconds: 800);

/// 안 건드리면 검게 덮는 시간
const screenOffAfter = Duration(seconds: 60);

/// 검게 덮인 채 이만큼 더 두면 대기 화면으로
const screenResetAfter = Duration(seconds: 10);

/// 두 번 톡톡으로 끈 화면은 이만큼 뒤 대기 화면으로
const doubleTapResetAfter = Duration(seconds: 5);
const doubleTapWithin = Duration(milliseconds: 300);

/// true 면 보드에서도 플러그를 화면에서만 켜고 끈다
const simulatePlugs = false;

/// 가전 id → Shelly 플러그 IP. 전력 노드가 꺼졌을 때 직접 켜고 끈다
const shellyPlugs = {'iron': '192.168.0.54', 'dryer': '192.168.0.53'};

/// [끄기] 뒤 이 안에 꺼짐이 확인되지 않으면 실패 (전류값은 1초마다 온다)
const applianceOffTimeout = Duration(seconds: 8);

/// 모두 출발한 뒤 인사 화면을 보여 주는 시간
const farewellHold = Duration(seconds: 10);

/// 귀가 화면 [다 했어요] 뒤 인사를 보여 주는 시간
const returnDoneHold = Duration(seconds: 5);

/// 출발하고 이 안에 다시 잡히면 귀가가 아니다
const returnGrace = Duration(minutes: 10);

/// 귀가 기록이 없는 사람은 이 시간 전부터 없던 물건을 "어제부터 없었어요" 로 본다
const trayAbsentFallback = Duration(hours: 8);

/// 트레이 구간 기록 보관 기간
const trayPresenceKeep = Duration(days: 30);

/// 현관에서 알아본 가족을 다시 귀가 화면으로 들이기까지
const doorReturnAgain = Duration(minutes: 10);

/// 카메라 펌웨어의 SERVER_URL 포트와 같아야 한다
const doorCamPort = 8000;

/// 대기(3fps) 중 최근 4장 가운데 3장에 얼굴이 있으면 감지 (약 1초)
const doorFaceWindow = 4;
const doorFaceNeeded = 3;

/// 카메라 RESULT_TIMEOUT_S 와 같다
const doorConfirmTimeout = Duration(seconds: 15);

/// 팝업 중 얼굴이 이만큼 안 보이면 사람이 갔다
const doorGoneAfter = Duration(seconds: 3);

/// 쓸 만한 얼굴을 이만큼 보고도 아무도 안 맞으면 모르는 사람 (감지 뒤 최소 대기 시간은 지나야)
const doorUnknownAfterFaces = 8;
const doorUnknownMinWait = Duration(seconds: 4);

/// 확정하려면 본 장 가운데 실제 얼굴 확률이 이 이상인 장이 하나는 있어야 한다 (ESP32 JPEG 은 실제 사람도 낮게 나온다)
const doorLiveThreshold = 0.3;

/// 얼굴은 맞는데 이만큼 지나도록 실제 얼굴 기준을 못 넘으면 사진 · 화면으로 본다
const doorSpoofAfter = Duration(seconds: 4);

/// 도어락이 UNLOCK 뒤 스스로 잠그기까지 (초, 닫힘 신호는 따로 없다)
const doorLockOpenSeconds = 5;

/// 아는 사람 인사 + 문 열림 · 닫힘을 보여 주는 시간 (초)
const doorKnownHold = doorLockOpenSeconds + 1;

/// 다른 화면을 쓰는 중일 때 [귀가 화면 열기] 창을 띄워 두는 시간 (초)
const doorBusyOfferHold = 10;

/// 모르는 사람을 더 지켜보는 시간 (초, 카메라 UNKNOWN_S 와 같다)
const doorUnknownHold = 30;

/// [문 열기] 뒤 "문을 열었어요" 를 보여 주는 시간 (초)
const doorOpenedHold = 3;

/// vision 답이 이만큼 안 오면 세션을 새로 연다
const doorVisionStuck = Duration(seconds: 3);

/// 프레임이 이만큼 안 오면 "연결 안 됨"
const doorCamStale = Duration(seconds: 20);

/// 하드웨어 없이 흐름을 넘겨 보는 개발용 패널. 배포할 때 false
const showDevPanel = true;

const weatherRefresh = Duration(minutes: 30);
const familyRefresh = Duration(minutes: 5);

/// PIR 로 화면을 켜는 시간: 출발 시각 remindBefore 전부터 이만큼 뒤까지
const pirAfterLeave = Duration(minutes: 30);
