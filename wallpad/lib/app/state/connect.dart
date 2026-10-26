part of '../app_state.dart';

extension AppConnect on AppState {
  Future<void> connect() async {
    AppClock.load();
    if (!onBoard) return;
    // DB 가 실패해도 장치 통신은 살리려고 DB 보다 먼저 띄운다
    broker.start().ignore();
    database.open();
    await repo.deleteDraftMembers(); // 온보딩 도중 꺼져 남은 임시 멤버
    final members = await repo.fetchMembers();
    users
      ..clear()
      ..addAll([for (final m in members) User('${m.id}', m.name, _colorFor(m.id))]);
    _pins
      ..clear()
      ..addAll({for (final e in (await repo.fetchPins()).entries) '${e.key}': e.value});
    for (final m in members) {
      if (_pins.containsKey('${m.id}')) continue;
      final hash = Pin.create(AppState.defaultPin);
      await repo.savePin(m.id, hash);
      _pins['${m.id}'] = hash;
    }
    _returnCheckOff
      ..clear()
      ..addAll({for (final id in await repo.fetchReturnCheckOff()) '$id'});
    events.clear(); // 예시 일정은 PC 용
    await _loadBelongings();
    await _loadProfiles();
    await _loadDayState();
    if (users.isEmpty) stage = Stage.welcome;
    _changed();
    _loadCalendarStatus();
    _startTray();
    _startPower();
    _startDoorCam();
    _startPir();
    // 첫 인식 카운트다운이 모델 로딩에 먹히지 않게 미리 올려 둔다
    vision.start().ignore();
  }

  Future<void> _loadProfiles() async {
    profiles
      ..clear()
      ..addAll({for (final e in (await repo.fetchProfiles()).entries) '${e.key}': e.value});
    essentials
      ..clear()
      ..addAll({for (final e in (await repo.fetchEssentials()).entries) '${e.key}': e.value});
  }

  // 월패드가 밤새 재시작돼도 귀가 판정과 두고 온 것이 남게 DB 에서 되살린다
  Future<void> _loadDayState() async {
    final today = _dayKey(), yesterday = _dayKey(daysAgo: 1);
    await repo.pruneDayItems(yesterday);
    departedAt
      ..clear()
      ..addAll({for (final e in (await repo.fetchOpenDepartures(today)).entries) '${e.key}': e.value});
    _checks.clear();
    _leftOut.clear();
    _notes.clear();
    final leftOut = <String, Map<String, (DateTime, Set<String>)>>{};
    final notes = <String, Map<String, (DateTime, List<(String, String)>)>>{};
    for (final r in await repo.fetchDayItems(yesterday)) {
      final id = '${r.memberId}';
      switch (r.kind) {
        case 'checked':
          if (r.day == today) checksOf(id).add(r.itemKey);
        case 'left_out':
          leftOut.putIfAbsent(id, () => {}).putIfAbsent(r.day, () => (r.at, {})).$2.add(r.itemKey);
        case 'note':
          notes.putIfAbsent(id, () => {}).putIfAbsent(r.day, () => (r.at, [])).$2.add((r.itemKey, r.name ?? ''));
      }
    }
    for (final e in leftOut.entries) {
      _leftOut[e.key] = e.value[e.value.keys.reduce((a, b) => a.compareTo(b) >= 0 ? a : b)]!;
    }
    for (final e in notes.entries) {
      _notes[e.key] = e.value[e.value.keys.reduce((a, b) => a.compareTo(b) >= 0 ? a : b)]!;
    }
  }
}
