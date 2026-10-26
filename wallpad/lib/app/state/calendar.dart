part of '../app_state.dart';

extension AppCalendar on AppState {
  Future<void> _loadCalendarStatus() async {
    final server = await _server;
    if (server == null) return;
    for (final u in List.of(users)) {
      try {
        final link = await server.status(u.id);
        u.calendarLinked = link != CalendarLink.notLinked;
        u.calendarNeedsReauth = link == CalendarLink.needsReauth;
      } catch (_) {
      }
    }
    _changed();
  }

  Future<void> newCalendarQr() async {
    stopCalendarQr();
    final gen = ++_qrGen;
    final id = userId;
    if (id == null) return;
    calendarLinkUrl = null;
    calendarLinkExpires = null;
    calendarError = null;
    _changed();
    final server = await _server;
    if (gen != _qrGen) return;
    if (server == null) {
      calendarError = DeviceConfig.exists
          ? '설정 파일(device.json) 내용이 잘못됐어요'
          : '월패드에 설정 파일(.config/leaveguard/device.json)이 없어요';
      _changed();
      return;
    }
    try {
      final s = await server.createSession(id);
      if (gen != _qrGen) return;
      calendarLinkUrl = s.url;
      calendarLinkExpires = s.expiresAt;
      _linkPoll = Timer.periodic(s.pollInterval, (_) => _pollLink(server, id, s, gen));
    } catch (_) {
      if (gen != _qrGen) return;
      calendarError = '서버에 연결하지 못했어요. 잠시 뒤 새 QR 을 만들어 주세요';
    }
    _changed();
  }

  void stopCalendarQr() {
    _linkPoll?.cancel();
    _linkPoll = null;
  }

  Future<void> _pollLink(CalendarServer server, String id, LinkSession s, int gen) async {
    if (_polling) return;
    if (DateTime.now().isAfter(s.expiresAt)) return stopCalendarQr();
    _polling = true;
    try {
      final status = await server.pollSession(s.id);
      if (gen != _qrGen) return;
      switch (status) {
        case LinkStatus.pending:
          return;
        case LinkStatus.linked:
          stopCalendarQr();
          userOf(id)
            ?..calendarLinked = true
            ..calendarNeedsReauth = false;
          _changed();
          await _loadEvents(id);
          return;
        case LinkStatus.denied:
          calendarError = '구글 로그인이 취소됐어요. 새 QR 을 만들어 주세요';
        case LinkStatus.failed:
          calendarError = '연동에 실패했어요. 새 QR 을 만들어 주세요';
        case LinkStatus.expired:
          calendarLinkExpires = DateTime.now();
      }
      stopCalendarQr();
      _changed();
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  Future<void> refreshCalendar() async {
    final id = userId;
    if (id == null || userOf(id)?.calendarLinked != true || _devLinked.contains(id)) return;
    await _loadEvents(id);
  }

  Future<void> _loadEvents(String id) async {
    final server = await _server;
    final u = userOf(id);
    if (server == null || u == null) return;
    try {
      final r = await server.fetchToday(id);
      u
        ..calendarLinked = r.link != CalendarLink.notLinked
        ..calendarNeedsReauth = r.link == CalendarLink.needsReauth;
      events[id] = [for (final e in r.events) CalendarEvent(e.time, e.title)];
      if (userId == id) calendarFailed = false;
    } catch (_) {
      if (userId == id) calendarFailed = true;
    }
    _changed();
  }

  void calendarSaved() {
    final u = user;
    if (u == null) return;
    stopCalendarQr();
    _devLinked.add(u.id);
    u
      ..calendarLinked = true
      ..calendarNeedsReauth = false;
    events.putIfAbsent(u.id, () => const [CalendarEvent('11:00', '치과'), CalendarEvent('18:00', '운동')]);
    _changed();
  }

  Future<void> disconnectCalendar() async {
    final u = user;
    if (u == null) return;
    calendarError = null;
    final server = await _server;
    if (server != null && !_devLinked.contains(u.id)) {
      try {
        await server.unlink(u.id);
      } catch (_) {
        calendarError = '서버에서 연동을 끊지 못했어요. 다시 시도해 주세요';
        _changed();
        return;
      }
    }
    _devLinked.remove(u.id);
    u
      ..calendarLinked = false
      ..calendarNeedsReauth = false;
    events.remove(u.id);
    calendarFailed = false;
    _changed();
  }
}
