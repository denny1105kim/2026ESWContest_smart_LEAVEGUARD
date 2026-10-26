part of '../app_state.dart';

extension AppDev on AppState {
  void demoMorning() {
    final now = AppClock.now();
    _demoJump(_nextWorkday(DateTime(now.year, now.month, now.day, 7, 30)));
  }

  // 주말을 건너뛰지 않는다. 건너뛰면 귀가 때 남긴 메모가 "어젯밤" 것이 아니게 된다
  void demoNextMorning() {
    final now = AppClock.now();
    _demoJump(DateTime(now.year, now.month, now.day + 1, 7, 30));
  }

  DateTime _nextWorkday(DateTime d) {
    final id = listedUsers.firstOrNull?.id;
    var day = d;
    for (var i = 0; i < 7 && !workdayOf(id, day); i++) {
      day = DateTime(day.year, day.month, day.day + 1, day.hour, day.minute);
    }
    return day;
  }

  void demoEvening() {
    final now = AppClock.now();
    _demoJump(DateTime(now.year, now.month, now.day, 18, 0));
  }

  void _demoJump(DateTime at) {
    _greetTimer?.cancel();
    greetingUserId = null;
    _doorReset(tellCamera: true);
    setScreenClock(at);
    go(Stage.idle);
  }

  void demoResetAll() {
    _greetTimer?.cancel();
    greetingUserId = null;
    _doorReset(tellCamera: true);
    setScreenClock(null);
    departedAt.clear();
    _checks.clear();
    _leftOut.clear();
    _notes.clear();
    memoSeen.clear();
    _situation.clear();
    _acks.clear();
    _lastReturnAt.clear();
    _devTray.clear();
    if (devTomorrowRain) setDevTomorrowRain(false);
    if (onBoard) repo.resetDayState();
    _recomputeTray();
    go(Stage.idle);
  }

  Future<void> demoResetUsers() async {
    for (final u in users.toList()) {
      deleteUser(u);
    }
    drafts.clear();
    demoResetAll();
    if (onBoard) {
      await repo.resetMembers();
      await _loadBelongings();
      _recomputeTray();
    }
    go(Stage.welcome);
  }

  void devDoorDetected() {
    if (doorPhase == DoorPhase.idle) _doorDetected();
  }

  void devDoorKnown(String id) {
    if (doorPhase == DoorPhase.idle) _doorDetected();
    _doorKnown(id);
  }

  void devDoorUnknown() {
    if (doorPhase == DoorPhase.idle) _doorDetected();
    _doorUnknown();
  }

  void devDoorGone() => _doorReset(tellCamera: true);

  void setDoorOnline(bool v) {
    doorOnline = v;
    _changed();
  }

  void setTrayOffline(bool v) {
    trayOffline = v;
    _changed();
  }

  void setDevUvHigh(bool v) {
    devUvHigh = v;
    if (v) {
      uv = const UvToday(6, 12);
      _changed();
    } else {
      refreshUv(force: true);
    }
  }

  void setDevBigGap(bool v) {
    devBigGap = v;
    final w = weather;
    if (v && w != null) {
      weather = Weather(location: w.location, tempC: w.tempC, highC: w.highC, lowC: w.highC - 14, precipProb: w.precipProb, icon: w.icon, label: w.label);
      _changed();
    } else {
      refreshWeather(force: true);
    }
  }

  void setDevTomorrowRain(bool v) {
    devTomorrowRain = v;
    if (v) {
      weatherTomorrow = Weather(location: weather?.location ?? '', tempC: 17, highC: 19, lowC: 8, precipProb: 70, icon: Icons.umbrella_rounded, label: '비');
      _changed();
    } else {
      refreshWeather(force: true);
    }
  }

  void setDevAirBad(bool v) {
    devAirBad = v;
    if (v) {
      air = const AirQuality(now: AirNow(station: '개발용', pm25: 48, pm10: 70, dataTime: '2026-01-01 08:00'));
      _changed();
    } else {
      refreshAir(force: true);
    }
  }

  void cycleTray(String belongingId) {
    const order = [TrayStatus.onTray, TrayStatus.taken, TrayStatus.notReturned, TrayStatus.takenByOther];
    final cur = _devTray[belongingId] ?? statusOf(belongingId, userId);
    final i = order.indexOf(cur);
    _watchReady(() => _devTray[belongingId] = order[(i + 1) % order.length]);
  }

  void setFailNextTurnOff(bool v) {
    failNextTurnOff = v;
    _changed();
  }

  void setCalendarFailed(bool v) {
    calendarFailed = v;
    _changed();
  }
}
