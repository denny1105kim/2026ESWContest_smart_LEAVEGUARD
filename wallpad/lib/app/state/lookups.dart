part of '../app_state.dart';

extension AppLookups on AppState {
  DateTime get screenNow => clock();

  User? get user => userOf(userId);
  User? userOf(String? id) => users.where((u) => u.id == id).firstOrNull;

  List<Belonging> belongingsOf(String? id) => belongings.where((b) => b.ownedBy(id)).toList();

  List<Belonging> get myBelongings => belongingsOf(userId);

  String ownerNames(Belonging b) => [for (final u in b.userIds) if (userOf(u)?.name case final n? when n.isNotEmpty) n].join(', ');

  List<ChecklistEntry> get todayList => todayListOf(userId);

  List<ChecklistEntry> todayListOf(String? id) {
    if (id == null) return const [];
    final ahead = _screenDaysAhead == 1;
    final dust = ahead ? air?.tomorrow : air?.grade;
    final weatherList = _weatherEntries(id, '', weatherToday, dust, ahead ? (dust == null ? null : '미세먼지 ${dust.label} · 예보') : air?.reason, ahead ? uvTomorrow : uv);
    final profile = profiles[id];
    final restDay = profile != null && !profile.goesOutOn(clock()) && profile.weekend == 'rest';
    return [
      ...weatherList,
      if (!restDay)
        for (final n in essentials[id] ?? const <String>[])
          if (!weatherList.any((w) => n.startsWith(w.name))) ChecklistEntry('e_${id}_$n', n, EntryKind.essential, '꼭 챙길 것', Icons.push_pin_rounded),
      if (!trayLive)
        for (final b in leftOutOf(id, daysAgo: 1)) ChecklistEntry('l_${b.id}', b.name, EntryKind.leftOut, '어제 밖에 두고 왔어요', b.icon),
      for (final (nid, name) in notesOf(id, daysAgo: 1)) ChecklistEntry(nid, name, EntryKind.note, '어젯밤 귀가할 때 적어 둠', Icons.edit_note_rounded),
    ];
  }

  List<ChecklistEntry> tomorrowListOf(String? id) {
    if (id == null) return const [];
    final known = _screenDaysAhead == 0; // 받아 둔 예보는 실제 오늘 · 내일 것뿐이다
    final dust = known ? air?.tomorrow : null;
    return [
      ..._weatherEntries(id, 't', weatherNextDay, dust, dust == null ? null : '미세먼지 ${dust.label} · 내일 예보', known ? uvTomorrow : null, day: '내일 · '),
      for (final b in leftOutOf(id, daysAgo: 0)) ChecklistEntry('tl_${b.id}', b.name, EntryKind.leftOut, '오늘 밖에 두고 왔어요', b.icon),
      for (final (nid, name) in notesOf(id, daysAgo: 0)) ChecklistEntry(nid, name, EntryKind.note, '직접 적음 · 내일 아침에 떠요', Icons.edit_note_rounded),
    ];
  }

  int get _screenDaysAhead {
    final s = clock(), r = DateTime.now();
    return DateTime(s.year, s.month, s.day).difference(DateTime(r.year, r.month, r.day)).inDays;
  }

  Weather? get weatherToday => _screenDaysAhead == 1 ? weatherTomorrow ?? weather : weather;

  Weather? get weatherNextDay => _screenDaysAhead == 0 ? weatherTomorrow : null;

  static List<ChecklistEntry> _weatherEntries(String id, String p, Weather? w, AirGrade? dust, String? dustWhy, UvToday? uv, {String day = ''}) => [
        if (w != null && w.precipProb >= 50)
          ChecklistEntry('${p}w_umbrella_$id', '우산', EntryKind.weather, '${day.isEmpty ? '날씨 · ' : day}${w.label} · 강수 ${w.precipProb}%', Icons.umbrella_rounded),
        if (w != null)
          if (_coat(id, p, w, day) case final coat?) coat,
        if (dust?.needsMask ?? false) ChecklistEntry('${p}a_mask_$id', '마스크', EntryKind.air, dustWhy ?? '', Icons.masks_rounded),
        if (uv != null && uv.needsSunscreen)
          ChecklistEntry('${p}u_sun_$id', '선크림', EntryKind.uv, '자외선 $day${uv.label} ${uv.max} · ${uv.hour}시 무렵', Icons.wb_sunny_rounded),
      ];

  static ChecklistEntry? _coat(String id, String p, Weather w, String day) {
    final gap = w.highC - w.lowC;
    if (gap <= 5) return null;
    final why = '$day일교차 $gap° · 아침 ${w.lowC}° 낮 ${w.highC}°';
    if (gap <= 8) return ChecklistEntry('${p}w_coat_$id', '얇은 겉옷', EntryKind.weather, why, Icons.checkroom_rounded);
    return ChecklistEntry('${p}w_coat_$id', '겉옷', EntryKind.weather, gap >= 13 ? '$why · 꼭 챙기세요' : why, Icons.checkroom_rounded);
  }

  List<Belonging> leftOutOf(String id, {required int daysAgo}) {
    final rec = _leftOut[id];
    if (rec == null || !_isDaysAgo(rec.$1, daysAgo)) return const [];
    return belongingsOf(id).where((b) => rec.$2.contains(b.id) && !(trayLive && statusOf(b.id, id) == TrayStatus.onTray)).toList();
  }

  List<(String, String)> notesOf(String id, {required int daysAgo}) {
    final rec = _notes[id];
    if (rec == null || !_isDaysAgo(rec.$1, daysAgo)) return const [];
    return rec.$2;
  }

  bool returnAnswered(String id, {int daysAgo = 0}) {
    final rec = _leftOut[id];
    return rec != null && _isDaysAgo(rec.$1, daysAgo);
  }

  bool _isDaysAgo(DateTime at, int days) {
    final now = clock();
    return DateUtils.isSameDay(at, DateTime(now.year, now.month, now.day - days));
  }

  String _dayKey({int daysAgo = 0}) {
    final now = clock();
    return dayKey(DateTime(now.year, now.month, now.day - daysAgo));
  }

  Set<String> get checked => checksOf(userId);
  Set<String> checksOf(String? id) => _checks.putIfAbsent(id ?? '', () => {});

  bool get trayLive => onBoard && !trayOffline;

  TrayInfo trayInfoOf(String itemId, String? viewerId) {
    if (trayOffline) return const TrayInfo(TrayStatus.unknown);
    final dev = _devTray[itemId];
    if (dev != null) {
      final at = dev == TrayStatus.onTray || dev == TrayStatus.taken ? null : clock().subtract(const Duration(hours: 1));
      return TrayInfo(dev, at: at, by: dev == TrayStatus.takenByOther ? 'u2' : null);
    }
    final b = belongingById(itemId);
    if (!onBoard || b == null) return const TrayInfo(TrayStatus.taken);
    return trayStatusOf(
      segments: _presence[itemId] ?? const [],
      acked: _acks.contains('$itemId:$viewerId'),
      lastReturnAt: _lastReturnAt[viewerId],
      cameraOnline: !trayOffline,
      now: clock(),
      fallback: trayAbsentFallback,
      viewerId: viewerId ?? '',
      shared: b.shared,
    );
  }

  TrayStatus statusOf(String itemId, String? viewerId) => trayInfoOf(itemId, viewerId).status;

  List<Belonging> leftOnTray(String? id) =>
      belongingsOf(id).where((b) => statusOf(b.id, id) == TrayStatus.onTray && !checksOf(id).contains(trayCheckKey(b.id))).toList();

  static String trayCheckKey(String belongingId) => 'b_$belongingId';

  int trayCountedOf(String? id) => belongingsOf(id).where((b) => statusOf(b.id, id) != TrayStatus.unknown).length;

  List<ChecklistEntry> uncheckedOf(String? id) => todayListOf(id).where((e) => !checksOf(id).contains(e.id)).toList();

  int remainingOf(String? id) => leftOnTray(id).length + uncheckedOf(id).length;

  bool readyOf(String? id) => remainingOf(id) == 0;

  bool departed(String? id) => departedAt.containsKey(id);

  DateTime? returnedTodayAt(String? id) {
    final at = _lastReturnAt[id];
    return at != null && _isDaysAgo(at, 0) ? at : null;
  }

  bool freshReturn(String id) => departed(id) || returnedTodayAt(id) == null;

  List<Belonging> takenTodayOf(String? id) => belongingsOf(id).where((b) => takenToday(trayInfoOf(b.id, id), id)).toList();

  bool takenToday(TrayInfo i, String? viewerId) {
    if (i.status == TrayStatus.taken) return true;
    final at = i.at;
    return i.status == TrayStatus.notReturned && !i.heldByOther(viewerId) && at != null && _isDaysAgo(at, 0);
  }

  int daysAway(TrayInfo i) {
    final at = i.at;
    if (at == null) return 0;
    final now = clock();
    return DateTime(now.year, now.month, now.day).difference(DateTime(at.year, at.month, at.day)).inDays;
  }

  List<String> get stillHome => [for (final id in engaged) if (!departed(id)) id];

  List<User> get tabOrder => [
        for (final id in engaged)
          if (userOf(id) case final u?) u,
        for (final u in listedUsers) if (!engaged.contains(u.id)) u,
      ];

  // 나가고 돌아오는 시각의 한가운데부터 새벽 4시 전까지 (패턴이 없으면 15시부터)
  bool returnTimeOf(String id) {
    final now = clock();
    final m = now.hour * 60 + now.minute;
    if (m < 4 * 60) return true;
    final p = profiles[id];
    final leave = parseMinutes(p?.leaveTime), back = parseMinutes(p?.returnTime);
    final from = leave != null && back != null && back > leave ? (leave + back) ~/ 2 : 15 * 60;
    return m >= from;
  }

  String get outingWord {
    final now = clock();
    return workdayOf(userId, now) && now.hour >= 5 && now.hour < 11 ? '출근' : '외출';
  }

  bool workdayOf(String? id, DateTime day) => profiles[id]?.goesOutOn(day) ?? day.weekday <= 5;

  String get situation => _situation[userId] ?? outingWord;

  void cycleSituation() {
    if (userId == null) return;
    final i = AppState.situations.indexOf(situation);
    _situation[userId!] = AppState.situations[(i + 1) % AppState.situations.length];
    _changed();
  }

  // 등록 중인 사람은 세지 않는다
  bool get isFamily => listedUsers.length >= 2;

  List<Appliance> get onAppliances => appliances.where((a) => a.isOn).toList();

  List<CalendarEvent> get myEvents => events[userId] ?? const [];

  List<CalendarEvent> get myRemainingEvents {
    final now = clock();
    final at = hhmm(now);
    return [for (final e in myEvents) if (!RegExp(r'^\d\d:\d\d$').hasMatch(e.time) || e.time.compareTo(at) >= 0) e];
  }

  List<Belonging> notBackOf(String? id) => belongingsOf(id).where((b) {
        final i = trayInfoOf(b.id, id);
        return const [TrayStatus.taken, TrayStatus.notReturned, TrayStatus.acknowledged].contains(i.status) && !i.heldByOther(id);
      }).toList();

  String _id() => 'x${_nextId++}';

  Color _colorFor(int index) => AppState._userColors[index % AppState._userColors.length];
}
