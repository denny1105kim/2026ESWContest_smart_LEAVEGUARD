part of '../app_state.dart';

/// 안 건드리면 검게 덮고, 더 두면 대기 화면으로 돌려 다음 사람이 남의 화면을 보지 않게 한다
extension AppScreen on AppState {
  static const _exempt = [Stage.idle, Stage.welcome, Stage.identifying]; // 인식 화면은 자체 카운트다운이 있다

  void touched() {
    final wasOff = screenOff;
    screenOff = false;
    _armScreenOff();
    if (wasOff) _changed();
  }

  void watchScreen(bool on) {
    _screenWatched = on;
    if (on) {
      _armScreenOff();
    } else {
      _screenOffTimer?.cancel();
      _screenResetTimer?.cancel();
      screenOff = false;
    }
  }

  void _armScreenOff() {
    _screenOffTimer?.cancel();
    _screenResetTimer?.cancel();
    if (!_screenWatched) return;
    if (_exempt.contains(stage)) {
      if (screenOff) {
        screenOff = false;
        _changed();
      }
      return;
    }
    _screenOffTimer = Timer(screenOffAfter, () {
      screenOff = true;
      _changed();
      _screenResetTimer = Timer(screenResetAfter, _resetToIdle);
    });
  }

  // 첫 누름이 무언가를 바꿨거나 그 사이 프레임이 흘렀으면 두 번 톡톡이 아니다
  void pointerDown(Offset at, {bool doubleTapOff = true}) {
    final frame = SchedulerBinding.instance.currentSystemFrameTimeStamp, lastFrame = _lastDownFrame;
    final now = DateTime.now(), last = _lastDownAt, lastAt = _lastDownPos, quiet = _changeSeq == _lastDownSeq;
    _lastDownAt = now;
    _lastDownPos = at;
    _lastDownSeq = _changeSeq;
    _lastDownFrame = frame;
    final soon = last != null && now.difference(last) < doubleTapWithin && lastFrame != null && frame - lastFrame < doubleTapWithin;
    if (doubleTapOff && quiet && soon && !screenOff && lastAt != null && (at - lastAt).distance < 40) {
      _lastDownAt = null; // 세 번째 누름은 새로 센다
      return screenOffNow();
    }
    touched();
  }

  void screenOffNow() {
    if (!_screenWatched || _exempt.contains(stage)) return;
    _screenOffTimer?.cancel();
    _screenResetTimer?.cancel();
    screenOff = true;
    _changed();
    _screenResetTimer = Timer(doubleTapResetAfter, _resetToIdle);
  }

  void setScreenClock(DateTime? at) {
    final day = _dayKey(), before = clock();
    AppClock.set(at);
    if (clock().isBefore(before)) _forgetFuture(clock());
    _changed();
    if (_dayKey() == day) return;
    if (onBoard) {
      _loadDayState().then((_) => _changed());
    } else {
      departedAt.clear();
      _checks.clear();
      _changed();
    }
  }

  // 화면 시각을 뒤로 옮기면 그 뒤의 기록은 아직 오지 않은 일이다
  void _forgetFuture(DateTime now) {
    for (final list in _presence.values) {
      for (var i = 0; i < list.length; i++) {
        list[i] = list[i].clampedTo(now);
      }
    }
    _lastReturnAt.removeWhere((_, t) => t.isAfter(now));
    departedAt.removeWhere((_, t) => t.isAfter(now));
    if (onBoard) repo.clampPresence(now);
  }

  void _resetToIdle() {
    screenOff = false;
    if (stage == Stage.onboarding) {
      for (final id in drafts.toList()) {
        final u = userOf(id);
        if (u != null) discardMember(u);
      }
      stopCalendarQr();
    }
    trayPeek = false;
    activeQuestion = null;
    go(Stage.idle);
  }
}
