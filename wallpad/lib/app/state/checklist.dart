part of '../app_state.dart';

extension AppChecklist on AppState {
  void toggleCheck(String id) => _watchReady(() => _setCheck(userId, id, !checked.contains(id)));

  void takeFromTray(String belongingId) => _watchReady(() => _setCheck(userId, AppLookups.trayCheckKey(belongingId), true));

  void _setCheck(String? who, String id, bool on) {
    on ? checksOf(who).add(id) : checksOf(who).remove(id);
    final memberId = int.tryParse(who ?? '');
    if (!onBoard || memberId == null) return;
    on ? repo.putDayItem(memberId, _dayKey(), 'checked', id, at: clock()) : repo.deleteDayItem(memberId, _dayKey(), 'checked', id);
  }


  void _watchReady(void Function() change) {
    change();
    final settled = stage == Stage.returning ? notBackOf(userId).isEmpty : outgoing.every(readyOf);
    if (prompt == Prompt.skip && settled) prompt = Prompt.none;
    _changed();
  }

  void toggleFamilyTodo(String id) {
    final t = familyTodos.firstWhere((t) => t.id == id);
    if (t.done) {
      t.doneAt = null;
      t.doneBy = null;
    } else {
      t.doneAt = DateTime.now();
      t.doneBy = user?.name;
    }
    _changed();
    _familyDone.save(DateTime.now(), {
      for (final t in familyTodos)
        if (t.doneAt != null) t.id: FamilyDone(t.doneAt!, t.doneBy),
    });
  }

  Future<void> refreshFamily({bool force = false}) async {
    if (_familyLoading) return;
    final at = familyAt;
    if (!force && at != null && DateTime.now().difference(at) < familyRefresh) return;
    _familyLoading = true;
    try {
      final server = await _server;
      if (server == null) return;
      final day = await server.fetchFamilyToday();
      familyAt = DateTime.now();
      switch (day.state) {
        case FamilyCalendar.none || FamilyCalendar.needsReauth:
          familyTodos = [];
        case FamilyCalendar.ok:
          // 방금 누른 체크가 파일에 쓰이기 전일 수 있어 이미 있던 일정은 화면 상태를 따른다
          final now = DateTime.now();
          final saved = _familyDone.load(now);
          final sameDay = at != null && DateUtils.isSameDay(at, now);
          final before = {if (sameDay) for (final t in familyTodos) t.id: t};
          familyTodos = [
            for (final e in day.today)
              FamilyTodo(e.id, e.title, e.timeLabel)
                ..doneAt = before.containsKey(e.id) ? before[e.id]!.doneAt : saved[e.id]?.at
                ..doneBy = before.containsKey(e.id) ? before[e.id]!.doneBy : saved[e.id]?.by,
          ];
      }
    } catch (e) {
      debugPrint('LeaveGuard: 가족 일정을 받지 못함 ($e)');
    } finally {
      _familyLoading = false;
      _changed();
    }
  }

  void askSkip() {
    prompt = Prompt.skip;
    _changed();
  }

  void closePrompt() {
    prompt = Prompt.none;
    _changed();
  }

  void depart() {
    final id = userId;
    if (id == null || departed(id)) return;
    final now = clock();
    for (final who in outgoing) {
      if (departed(who)) continue;
      departedAt[who] = now;
      _recordMemberEvent(who, 'departed', now);
    }
    // 이번에 화면을 안 본 가족도 집에 있을 수 있어 가족 전체로 본다
    final nobodyHome = listedUsers.every((u) => departed(u.id));
    if (nobodyHome && stillHome.isEmpty && onAppliances.isNotEmpty) {
      prompt = Prompt.lastOut;
    } else {
      prompt = Prompt.none;
      if (stillHome.isEmpty) _closeSoon();
    }
    _changed();
  }

  Future<void> finishLastOut({required bool turnOffAll}) async {
    prompt = Prompt.none;
    _changed();
    if (turnOffAll) await Future.wait([for (final a in onAppliances) turnOff(a.id)]);
    _closeSoon();
  }

  void _closeSoon() {
    _farewellTimer?.cancel();
    _farewellTimer = Timer(farewellHold, () {
      if (stage == Stage.checklist) go(Stage.idle);
    });
  }
}
