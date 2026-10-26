import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../features/auth/pin.dart';
import '../features/belongings/gallery_matcher.dart';
import '../features/belongings/learning.dart';
import '../features/belongings/observation.dart';
import '../features/belongings/state_reducer.dart';
import '../features/belongings/tray_status.dart';
import '../features/calendar/calendar_server.dart';
import '../core/config/app_clock.dart';
import '../core/config/device_config.dart';
import '../core/config/constants.dart';
import '../core/config/scan_config.dart';
import '../device/camera/vision.dart';
import '../device/doorcam/door_cam_server.dart';
import '../device/power_link.dart' show PowerLink;
import '../core/data/models.dart' show BelongingQuestion, BelongingView, MemberProfile, OwnedBelonging, Presence;
import '../features/weather/air_quality.dart';
import '../features/weather/kma_weather.dart';
import '../features/weather/uv_index.dart';
import '../features/weather/weather_location.dart';
import '../shared/time_text.dart';
import 'backend.dart';
import 'family_done.dart';
import 'models.dart';

part 'state/lookups.dart';
part 'state/connect.dart';
part 'state/tray.dart';
part 'state/power.dart';
part 'state/flow.dart';
part 'state/auth.dart';
part 'state/members.dart';
part 'state/checklist.dart';
part 'state/group.dart';
part 'state/dev.dart';
part 'state/belongings.dart';
part 'state/calendar.dart';
part 'state/weather.dart';
part 'state/return_check.dart';
part 'state/doorcam.dart';
part 'state/pir.dart';
part 'state/screen.dart';

enum Stage { welcome, onboarding, idle, identifying, userSelect, checklist, returning, settings }

enum SettingsPane { belongings, calendar, users, wifi, appliances, clock, profile }

enum AuthPurpose { pick, switchTo, delete, create }

class AuthRequest {
  final String userId;
  final AuthPurpose purpose;
  final void Function() then;

  const AuthRequest(this.userId, this.purpose, this.then);
}

enum PinResult { ok, wrong, locked }

/// 앱 전체 상태. 메서드는 state/*.dart 의 extension 에 역할별로 나눠 둔다
class AppState extends ChangeNotifier {
  Stage stage = Stage.idle;
  String? userId;

  String? greetingUserId;

  SettingsPane settingsPane = SettingsPane.belongings;

  bool calendarFromChecklist = false;

  Stage onboardingFrom = Stage.welcome;

  String? onboardingHost;

  final drafts = <String>{};

  final profiles = <String, MemberProfile>{};

  final essentials = <String, List<String>>{};

  static const _userColors = [
    Color(0xFF3B82F6), Color(0xFFEC4899), Color(0xFF14B8A6),
    Color(0xFFF59E0B), Color(0xFF8B5CF6), Color(0xFF22C55E), Color(0xFFEF4444),
  ];

  final users = [
    User('u1', '재현', const Color(0xFF3B82F6)),
    User('u2', '서연', const Color(0xFFEC4899)),
    User('u3', '도윤', const Color(0xFF14B8A6)),
  ];

  final belongings = [
    Belonging('b1', ['u1'], '지갑', Icons.account_balance_wallet_rounded, photos: 3),
    Belonging('b2', ['u1'], '사원증', Icons.badge_rounded, photos: 2),
    Belonging('b3', ['u1', 'u2'], '차 키', Icons.key_rounded, photos: 4),
    Belonging('b4', ['u2'], '이어폰', Icons.headphones_rounded, photos: 2),
  ];

  var familyTodos = <FamilyTodo>[];

  DateTime? familyAt;

  final _familyDone = FamilyDoneStore();
  var _familyLoading = false;

  final _situation = <String, String>{};

  static const situations = ['출근', '등교', '외출'];

  bool trayOffline = false;

  final appliances = onBoard
      ? [
          Appliance('iron', '고데기', '안방', Icons.iron_rounded, 0),
          Appliance('dryer', '드라이기', '욕실', Icons.air_rounded, 0),
        ]
      : [
          Appliance('a1', '다리미', '안방', Icons.iron_rounded, 0.8),
          Appliance('a2', '전기포트', '주방', Icons.coffee_maker_rounded, 0),
          Appliance('a3', '거실 조명', '거실', Icons.lightbulb_rounded, 0),
        ];

  // 전력 노드는 끄고 10초 뒤에야 IDLE 을 보내므로 그때까지 꺼진 걸로 둔다
  final _turnedOffAt = <String, DateTime>{};

  final events = <String, List<CalendarEvent>>{
    'u1': const [
      CalendarEvent('10:00', '팀 회의'),
      CalendarEvent('14:00', '병원'),
      CalendarEvent('19:30', '저녁 약속'),
    ],
  };

  Weather? weather;

  Weather? weatherTomorrow;

  String? weatherNotice;

  AirQuality? air;

  DateTime? airAt;
  var _airLoading = false;

  UvToday? uv;

  UvToday? uvTomorrow;
  DateTime? uvAt;
  var _uvLoading = false;

  DateTime? weatherAt;

  final _devTray = <String, TrayStatus>{'b1': TrayStatus.onTray, 'b3': TrayStatus.takenByOther};

  final memoSeen = <String>{};

  final _presence = <String, List<Presence>>{};

  final _acks = <String>{};

  final _lastReturnAt = <String, DateTime>{};

  Timer? _rescanTimer;
  DateTime? _lastRescanAt;

  final _checks = <String, Set<String>>{};

  final turningOff = <String>{};

  final turningOn = <String>{};

  final turnOffErrors = <String, String>{};

  bool failNextTurnOff = false;

  bool calendarFailed = false;

  late final Future<CalendarServer?> _server = CalendarServer.load();

  String? calendarLinkUrl;

  DateTime? calendarLinkExpires;

  String? calendarError;

  Timer? _linkPoll;

  final _devLinked = <String>{};

  final engaged = <String>[];

  final departedAt = <String, DateTime>{};

  Prompt prompt = Prompt.none;

  final group = <String>[];

  final groupPick = <String>{};

  Timer? _greetTimer, _farewellTimer, _weatherTimer, _familyTimer, _returnTimer;

  bool homecoming = false;

  bool returnDone = false;
  var _nextId = 100;

  final _returnCheckOff = <String>{};

  bool returnCheckOpen = false;

  final returnChecked = <String>{};

  bool returnAskLeftOut = false;

  bool returnCheckDone = false;

  final _leftOut = <String, (DateTime, Set<String>)>{};

  final _notes = <String, (DateTime, List<(String, String)>)>{};

  @visibleForTesting
  DateTime Function() clock = AppClock.now;

  final _rows = <String, OwnedBelonging>{};
  final _trayReducer = StateReducer(ttl: const Duration(seconds: 90)); // 노드는 멈춘 장면을 30초마다 다시 관측한다

  final _rejects = <String, List<Float32List>>{};

  final _questions = <String, BelongingQuestion>{};
  final _questionBusy = <String>{};

  // 직접 그린 자리의 후보 id = 이 값 + 소지품 id (노드 후보 id 와 겹치지 않게)
  static const watchIdBase = 1000000;

  // 자리 인코딩을 기다리는 동안 새 관측이 오면 옛 결과를 버린다
  var _watchSeq = 0;

  BelongingQuestion? activeQuestion;

  bool trayPeek = false;
  List<int>? trayPreselect;

  final _askedThisVisit = <String>{};

  BelongingObservation? trayScene;
  var trayMatches = <int, CandidateMatch>{};

  var trayUnknown = <ObservedCandidate>[];

  final _lastSeenBox = <String, List<int>>{};
  final _lastSeenAt = <String, DateTime>{};

  bool screenOff = false;
  Timer? _screenOffTimer, _screenResetTimer;

  // StageView 가 떠 있을 때만 화면 꺼짐 타이머를 돌린다
  bool _screenWatched = false;

  DateTime? _lastDownAt;
  Offset? _lastDownPos;
  var _lastDownSeq = 0, _changeSeq = 0;
  Duration? _lastDownFrame;

  DoorPhase doorPhase = DoorPhase.idle;

  bool doorOnline = false;

  Uint8List? doorFrame;

  // 회전한 프레임 기준 0~1 좌표
  Rect? doorFaceBox;

  // 카메라가 거꾸로 달렸을 때 프레임을 시계 방향으로 돌릴 각도
  int doorRotation = 0;

  int doorFaceFrames = 0;

  String? doorUserId;

  int doorSecondsLeft = 0;

  bool doorOpened = false;

  bool doorSpoofed = false;

  final _doorWindow = <bool>[];
  final _doorHitsBy = <int, int>{};
  var _doorFaces = 0;
  var _doorMaxLive = 0.0;
  DateTime? _doorStartedAt, _doorMatchedAt, _doorLastFaceAt, _doorFrameAt, _doorBusySince;
  VisionSession? _doorSession;
  Timer? _doorTimer, _doorTick, _doorWatch;

  Timer? _pirTick;

  AuthRequest? auth;

  final _pins = <String, PinHash>{};
  final _pinLocks = <String, PinLock>{};

  static const devPin = defaultPin;

  // PIN 을 쓰기 전에 등록한 사람에게 주는 기본값
  static const defaultPin = '0000';

  var _qrGen = 0;
  var _polling = false;

  var _weatherLoading = false;

  bool devUvHigh = false;

  bool devBigGap = false;

  bool devAirBad = false;

  bool devTomorrowRain = false;

  AppState() {
    if (!onBoard) {
      _loadCalendarStatus();
      for (final u in users) {
        _pins[u.id] = Pin.create(devPin);
      }
    }
    refreshWeather();
    _weatherTimer = Timer.periodic(weatherRefresh, (_) => refreshWeather(force: true));
    refreshFamily();
    _familyTimer = Timer.periodic(familyRefresh, (_) => refreshFamily(force: true));
  }

  // extension 에서는 notifyListeners 를 직접 부를 수 없다
  void _changed() {
    _changeSeq++;
    notifyListeners();
  }

  @override
  void dispose() {
    _greetTimer?.cancel();
    stopCalendarQr();
    _farewellTimer?.cancel();
    _weatherTimer?.cancel();
    _familyTimer?.cancel();
    _returnTimer?.cancel();
    _doorTimer?.cancel();
    _doorTick?.cancel();
    _doorWatch?.cancel();
    _pirTick?.cancel();
    _screenOffTimer?.cancel();
    _screenResetTimer?.cancel();
    super.dispose();
  }
}

final app = AppState();

class AppScope extends InheritedNotifier<AppState> {
  AppScope({super.key, required super.child}) : super(notifier: app);
}

// const 위젯은 부모가 다시 그려도 건너뛰므로 상태를 읽는 위젯은 직접 구독한다
AppState watch(BuildContext context) {
  context.dependOnInheritedWidgetOfExactType<AppScope>();
  return app;
}
