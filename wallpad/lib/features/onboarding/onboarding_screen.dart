import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/pin.dart';
import '../../shared/widgets/on_screen_keyboard.dart';
import '../../shared/widgets/pin_pad.dart';
import '../../shared/widgets/qr_panel.dart';
import '../../shared/widgets/swipe_adjust.dart';
import '../../core/data/models.dart' show MemberProfile, essentialCandidates, weekdayBits;
import '../../shared/hangul.dart';
import '../../app/app_state.dart';
import '../../app/models.dart';
import 'face_step.dart';
import 'ob_widgets.dart';
import 'tray_step.dart';
import '../../shared/time_text.dart';

part 'steps/name_pin.dart';
part 'steps/life_pattern.dart';
part 'steps/essentials.dart';
part 'steps/calendar.dart';
part 'steps/done.dart';
part 'steps/widgets.dart';

/// 멤버 한 명 온보딩. PIN 단계에서 임시 저장하고 완료 화면에서 확정한다.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _S { name, face, pin, weekday, leave, belongings, essentials, calendar, done }

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _idleLimit = Duration(minutes: 3);

  var _s = _S.name;
  final _history = <_S>[];
  late int _memberNo;

  var _composer = HangulComposer();
  String? _nameError;
  User? _user;
  var _saving = false;

  var _faces = <String, List<double>>{};
  var _pin = '';
  String? _firstPin;
  String? _pinMessage;

  String? _place; // work · home · school
  String? _mode; // fixed · none
  var _leave = 8 * 60;
  var _return = 18 * 60 + 30;
  var _days = weekdayBits; // 월~금
  var _remind = 20;
  final _essentials = <String>{};
  var _essentialsReady = false;

  Timer? _idle, _tick;

  @override
  void initState() {
    super.initState();
    _memberNo = app.users.length + 1;
    _touch();
  }

  @override
  void dispose() {
    _idle?.cancel();
    _tick?.cancel();
    app.stopCalendarQr();
    super.dispose();
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(_idleLimit, () {
      final u = _user;
      if (_s == _S.done && u != null) return app.finishOnboarding(u);
      _cancel();
    });
  }

  void _cancel() {
    _idle?.cancel();
    // 확인 창이 떠 있을 때 시간 초과되면 창이 남으므로 먼저 닫는다
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    final u = _user;
    if (u != null) app.discardMember(u);
    app.leaveOnboarding();
  }

  Future<void> _askCancel() async {
    final yes = await showDialog<bool>(context: context, barrierColor: const Color(0x991A2033), builder: (_) => const _CancelDialog());
    if (yes == true && mounted) _cancel();
  }

  String get _name => _composer.text.trim();

  void _go(_S next) {
    _leaving(_s);
    setState(() {
      _history.add(_s);
      _s = next;
    });
    _entering(next);
  }

  bool get _canBack => _s != _S.name && _history.isNotEmpty;

  void _back() {
    if (_history.isEmpty) return;
    _leaving(_s);
    final prev = _history.removeLast();
    setState(() => _s = prev);
    _entering(prev);
  }

  void _leaving(_S s) {
    if (s == _S.calendar) {
      app.stopCalendarQr();
      _tick?.cancel();
    }
  }

  void _entering(_S s) {
    if (s == _S.pin) {
      _pin = '';
      _firstPin = _pinMessage = null;
    }
    if (s == _S.calendar) {
      app.newCalendarQr();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
    if (s == _S.essentials && !_essentialsReady) {
      _essentialsReady = true;
      _essentials
        ..clear()
        ..addAll(_defaultEssentials());
    }
  }

  // 건너뛰기도 여기로 온다. 건너뛴 답은 null 로 남는다
  Future<void> _next() async {
    switch (_s) {
      case _S.name:
        final n = _name;
        if (n.isEmpty) return;
        if (app.users.any((u) => u.name == n && u.id != _user?.id)) return setState(() => _nameError = '같은 이름이 있어요');
        _go(_S.face);
      case _S.face:
        _toPin(const {});
      case _S.pin:
        break;
      case _S.weekday:
        if (_place == 'home') {
          _mode = 'none';
          await _saveProfile();
          _go(_S.belongings);
        } else {
          _go(_S.leave);
        }
      case _S.leave:
        _mode = 'fixed';
        await _saveProfile();
        _go(_S.belongings);
      case _S.belongings:
        _go(_S.essentials);
      case _S.essentials:
        await app.setEssentials(_user!.id, _essentials.toList());
        _go(_S.calendar);
      case _S.calendar:
        _go(_S.done);
      case _S.done:
        break;
    }
  }

  void _toPin(Map<String, List<double>> faces) {
    _faces = faces;
    _pin = '';
    _firstPin = _pinMessage = null;
    _go(_S.pin);
  }

  void _pressPin(String d) {
    _touch();
    if (_saving || _pin.length >= Pin.length) return;
    setState(() => _pin += d);
    if (_pin.length == Pin.length) Future.delayed(const Duration(milliseconds: 120), _pinEntered);
  }

  void _backPin() {
    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _pinEntered() {
    if (!mounted) return;
    final first = _firstPin;
    if (first == null) {
      return setState(() {
        _firstPin = _pin;
        _pin = '';
        _pinMessage = null;
      });
    }
    if (_pin != first) {
      return setState(() {
        _firstPin = null;
        _pin = '';
        _pinMessage = '두 번 누른 PIN 이 달라요 · 처음부터 다시 눌러 주세요';
      });
    }
    _saveMember(_pin);
  }

  Future<void> _saveMember(String pin) async {
    setState(() => _saving = true);
    try {
      final before = _user;
      final u = before == null ? await app.saveNewUser(_name, _faces, pin, draft: true) : await app.updateDraftUser(before, _name, _faces, pin);
      app.beginMember(u);
      _user = u;
      if (!mounted) return;
      setState(() => _saving = false);
      _go(_S.weekday);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _firstPin = null;
          _pin = '';
          _pinMessage = '저장하지 못했어요 · PIN 을 다시 눌러 주세요';
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    final u = _user;
    if (u == null) return;
    final fixed = _mode == 'fixed';
    await app.saveProfile(
      u.id,
      MemberProfile(
        weekdayPlace: _place,
        scheduleMode: _mode,
        leaveTime: fixed ? minutesText(_leave) : null,
        returnTime: fixed ? minutesText(_return) : null,
        days: fixed ? _days : null,
        remindBefore: fixed ? _remind : null,
      ),
    );
  }

  void _restart() {
    final done = _user;
    if (done != null) app.completeMember(done);
    app.stopCalendarQr();
    _tick?.cancel();
    setState(() {
      _s = _S.name;
      _history.clear();
      _memberNo = app.users.length + 1;
      _composer = HangulComposer();
      _nameError = null;
      _user = null;
      _saving = false;
      _faces = {};
      _pin = '';
      _firstPin = _pinMessage = null;
      _place = _mode = null;
      _leave = 8 * 60;
      _return = 18 * 60 + 30;
      _days = weekdayBits;
      _remind = 20;
      _essentials.clear();
      _essentialsReady = false;
    });
  }

  List<String> get _traySuggestions => [
        '지갑',
        if (_place == 'work') '사원증',
        if (_place == 'school') '학생증',
      ];

  List<String> get _manualCandidates {
    final onTray = {for (final b in app.myBelongings) b.name};
    return [for (final n in essentialCandidates) if (!onTray.contains(n)) n];
  }

  Set<String> _defaultEssentials() {
    final c = _manualCandidates.toSet();
    return {
      '휴대폰',
      if (_place == 'work') '사원증',
      if (_place == 'school') '학생증',
    }.where(c.contains).toSet();
  }

  int get _sideStep => switch (_s) {
        _S.name => 0,
        _S.face || _S.pin => 1,
        _S.weekday || _S.leave => 2,
        _S.belongings => 3,
        _S.essentials => 4,
        _S.calendar => 5,
        _S.done => 6,
      };

  double get _progress {
    final frac = switch (_s) {
      _S.pin => 0.5,
      _S.weekday => 0.33,
      _S.leave => 0.66,
      _ => 1.0,
    };
    return (_sideStep + frac) / 6;
  }

  String get _leaveWord => switch (_place) { 'work' => '출근', 'school' => '등교', _ => '외출' };

  String get _title => switch (_s) {
        _S.name => '어떻게 불러드리면 될까요?',
        _S.face => '얼굴을 등록해 주세요',
        _S.pin => _firstPin == null ? 'PIN 4자리를 정해 주세요' : '한 번 더 눌러 주세요',
        _S.weekday => '평일에는 어떤 형태로 지내세요?',
        _S.leave => '보통 언제 $_leaveWord하세요?',
        _S.belongings => '카메라로 내 물건을 등록할까요?',
        _S.essentials => '놓치면 안 되는 물건을 골라 주세요',
        _S.calendar => '내 일정도 함께 챙겨드릴까요?',
        _S.done => '',
      };

  @override
  Widget build(BuildContext context) {
    watch(context);
    return Listener(
      onPointerDown: (_) => _touch(),
      child: Material(
        color: Ob.bg,
        child: _s == _S.done ? _doneView() : _flowView(),
      ),
    );
  }

  Widget _flowView() {
    final skippable = _s.index >= _S.face.index && _s.index <= _S.calendar.index && _s != _S.pin && !_saving;
    final label = '${(_sideStep + 1).toString().padLeft(2, '0')} / 06    ·    ${Ob.steps[_sideStep]}';
    final shown = _user?.name ?? _name;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ObSidebar(memberNo: _memberNo, name: shown, step: _sideStep, avatarColor: _user?.color ?? Ob.green),
        Expanded(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(94, 0, 76, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 30),
                    ObHeader(label: label, progress: _progress, onSkip: skippable ? _next : null),
                    const SizedBox(height: 32),
                    Text(_title, style: Ob.title),
                    const SizedBox(height: 40),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, if (current != null) current]),
                        child: KeyedSubtree(key: ValueKey(_s), child: _body()),
                      ),
                    ),
                    // 화면 아래 OS 스와이프 영역을 피해 버튼을 위로 붙인다
                    SizedBox(height: 190, child: _bottom()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bottom() {
    final buttons = <Widget>[];
    void add(Widget w) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 15));
      buttons.add(w);
    }

    final canPrev = _canBack && !_saving;
    switch (_s) {
      case _S.name:
        break;
      case _S.face:
      case _S.pin:
        if (canPrev) add(ObButton('←  이전', primary: false, width: 200, onTap: _back));
      case _S.calendar:
        if (canPrev) add(ObButton('←  이전', primary: false, width: 200, onTap: _back));
        final linked = app.user?.calendarLinked == true;
        add(ObButton(linked ? '다음  →' : '나중에 연결하기', width: linked ? 215 : 260, onTap: _next));
      default:
        if (canPrev) add(ObButton('←  이전', primary: false, width: 200, onTap: _back));
        add(ObButton('다음  →', onTap: _canNext ? _next : null));
    }
    return Align(
      alignment: Alignment.topCenter,
      child: Row(
        children: [
          _CancelButton(onTap: _saving ? null : _askCancel),
          const Spacer(),
          ...buttons,
        ],
      ),
    );
  }

  bool get _canNext => switch (_s) {
        _S.weekday => _place != null,
        _S.leave => _days != 0,
        _ => true,
      };

  Widget _body() => switch (_s) {
        _S.name => _nameBody(),
        _S.face => FaceStep(onDone: _toPin, saving: _saving),
        _S.pin => _pinBody(),
        _S.weekday => _cards([
            ('work', Icons.work_outline_rounded, '회사에 출근해요'),
            ('home', Icons.home_outlined, '재택근무해요'),
            ('school', Icons.school_outlined, '학교에 다녀요'),
          ], _place, (v) => setState(() => _place = v), perRow: 3, height: 260),
        _S.leave => _leaveBody(),
        _S.belongings => TrayStep(suggestions: _traySuggestions),
        _S.essentials => _essentialsBody(),
        _S.calendar => _calendarBody(),
        _S.done => const SizedBox(),
      };

  // extension 에서는 setState 를 직접 못 부른다
  void _setState(VoidCallback fn) => setState(fn);
}
