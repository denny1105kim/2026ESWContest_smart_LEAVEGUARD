import 'package:flutter/material.dart';

import '../belongings/tray_status.dart';
import '../../core/config/app_clock.dart';
import '../../core/config/constants.dart';
import '../../app/app_state.dart';
import '../../app/backend.dart';
import '../../app/models.dart';
import '../../shared/widgets/on_screen_keyboard.dart';
import '../appliances/appliance_sheet.dart';
import '../appliances/thinq_sim.dart';
import 'checklist_screen.dart';
import 'voice_memo_dialog.dart';
import '../../shared/time_text.dart';

// AppState 를 ViewData 로 바꾸는 곳은 여기뿐이다

String _source(DateTime fetchedAt) => '기상청 · ${hhmm(AppClock.onScreen(fetchedAt))} 기준';

List<FamilyTodoViewData> _familyTodos(AppState app) => [
      if (app.isFamily)
        for (final t in app.familyTodos)
          FamilyTodoViewData(id: t.id, name: t.name, timeLabel: t.done ? hhmm(t.doneAt!) : t.timeLabel, isDone: t.done, doneBy: t.doneBy),
    ];

List<ApplianceViewData> _appliances(AppState app) => [
      for (final a in app.appliances)
        ApplianceViewData(
          id: a.id,
          name: a.name,
          room: a.room,
          currentAmp: a.currentA,
          icon: a.icon,
          isOn: a.isOn,
          plugOn: app.plugOn(a.id),
          isBusy: app.turningOff.contains(a.id) || app.turningOn.contains(a.id),
          errorMessage: app.turnOffErrors[a.id],
          status: _plugStatus(a),
        ),
      for (final d in ThinqSim.instance.mainDevices)
        ApplianceViewData(
          id: d.id,
          name: d.kind,
          room: d.room,
          currentAmp: 0,
          icon: _thinqIcon(d.kind),
          isOn: false,
          status: d.isRobot && !d.isOn && d.cleanAt != null ? '${d.status} · ${d.cleanAt} 청소' : d.status,
          alert: d.tone == ThinqTone.running || d.tone == ThinqTone.done,
          thinq: true,
        ),
    ];

IconData _thinqIcon(String kind) => switch (kind) {
      '세탁기' || '워시타워' => Icons.local_laundry_service_rounded,
      '건조기' => Icons.dry_cleaning_rounded,
      '스타일러' => Icons.checkroom_rounded,
      '식기세척기' => Icons.countertops_rounded,
      '로봇청소기' => Icons.cleaning_services_rounded,
      '에어컨' => Icons.ac_unit_rounded,
      '공기청정기' => Icons.air_rounded,
      '오븐' => Icons.microwave_rounded,
      '냉장고' => Icons.kitchen_rounded,
      _ => Icons.devices_other_rounded,
    };

// 화면 시각을 옮겨 둬서 예보 범위 밖이면 같은 시(時)의 예보로 대신한다
WeatherHour? _hourAt(List<WeatherHour> hours, DateTime at) =>
    hours.where((x) => x.at == at).firstOrNull ?? (AppClock.shifted ? hours.where((x) => x.at.hour == at.hour).firstOrNull : null);

// 화면 시각을 옮겨 뒀을 때만 그 정시의 예보
WeatherHour? _screenHour(AppState app) {
  if (!AppClock.shifted) return null;
  final now = app.screenNow;
  return _hourAt(app.weather?.hours ?? const [], DateTime(now.year, now.month, now.day, now.hour));
}

List<WeatherHourViewData> _hours(AppState app, Weather w) {
  final hours = app.weather?.hours ?? const <WeatherHour>[];
  if (hours.isEmpty) return const [];
  final now = app.screenNow, shifted = _screenHour(app);
  final first = AppClock.shifted ? DateTime(now.year, now.month, now.day, now.hour) : hours.first.at;
  final out = <WeatherHourViewData>[];
  for (var i = 0; i < 7; i++) {
    final at = first.add(Duration(hours: 3 * i));
    final h = _hourAt(hours, at);
    if (h == null) continue;
    final live = i == 0 && shifted == null; // 실제 "지금"은 실황 기온
    out.add(WeatherHourViewData(
      label: i == 0 ? '지금' : hourText(at),
      temperature: live ? w.tempC : h.tempC,
      rainChance: h.precipProb,
      icon: live ? w.icon : h.icon,
    ));
  }
  return out;
}

WeatherViewData _weather(AppState app) {
  final w = app.weatherToday;
  if (w == null) {
    return WeatherViewData(location: '', temperature: 0, high: 0, low: 0, condition: '', rainChance: 0, notice: app.weatherNotice ?? '불러오는 중');
  }
  final now = _screenHour(app);
  return WeatherViewData(
    location: w.location,
    temperature: (now?.tempC ?? w.tempC).toDouble(),
    high: w.highC.toDouble(),
    low: w.lowC.toDouble(),
    condition: w.label,
    rainChance: w.precipProb,
    icon: now?.icon ?? w.icon,
    source: _source(app.weatherAt!),
    hours: _hours(app, w),
  );
}

TrayItemViewData _trayItem(AppState app, Belonging b) {
  final viewer = app.userId;
  final info = app.trayInfoOf(b.id, viewer);
  // 직접 챙김으로 누른 것은 트레이에 보여도 챙김
  final i = info.status == TrayStatus.onTray && app.checksOf(viewer).contains(AppLookups.trayCheckKey(b.id)) ? TrayInfo(TrayStatus.taken, at: info.at, by: info.by) : info;
  final who = i.by == null ? null : app.userOf(i.by)?.name;
  final when = i.at == null ? null : whenLabel(i.at!, app.screenNow);
  final other = i.heldByOther(viewer);
  final leftYesterday = viewer != null && app.leftOutOf(viewer, daysAgo: 1).any((x) => x.id == b.id);
  final byOther = '${who ?? '가족'}${when == null ? '' : ' · $when'} 가져감';
  String? detail, back;
  switch (i.status) {
    case TrayStatus.takenByOther:
      detail = byOther;
      back = detail;
    case TrayStatus.notReturned when leftYesterday:
      detail = '어제 밖에 두고 왔어요';
      back = detail;
    case TrayStatus.notReturned:
      detail = when == null ? '기록 없음' : '$when 가져감 · 없음';
      back = other ? byOther : when == null ? null : '$when 가져감';
    case TrayStatus.acknowledged:
      detail = '확인함';
      back = other ? byOther : null;
    case TrayStatus.taken:
      back = when == null ? null : '$when 가져감';
    case TrayStatus.onTray || TrayStatus.unknown:
      break;
  }
  return TrayItemViewData(
    id: b.id,
    name: b.name,
    icon: b.icon,
    state: switch (i.status) {
      TrayStatus.onTray => TrayState.onTray,
      TrayStatus.taken => TrayState.taken,
      TrayStatus.takenByOther => TrayState.takenByOther,
      TrayStatus.notReturned => TrayState.notReturned,
      TrayStatus.acknowledged => TrayState.acknowledged,
      TrayStatus.unknown => TrayState.unknown,
    },
    detail: detail,
    backDetail: back,
    heldByOther: other,
    takenToday: app.takenToday(i, viewer),
    daysAway: app.daysAway(i),
  );
}

ChecklistItemKind _kindOf(EntryKind k) => switch (k) {
      EntryKind.weather => ChecklistItemKind.weather,
      EntryKind.air => ChecklistItemKind.air,
      EntryKind.uv => ChecklistItemKind.uv,
      EntryKind.essential => ChecklistItemKind.essential,
      EntryKind.leftOut => ChecklistItemKind.leftOut,
      EntryKind.note => ChecklistItemKind.note,
    };

ChecklistItemViewData _item(AppState app, ChecklistEntry e) =>
    ChecklistItemViewData(id: e.id, title: e.name, reason: e.reason, isDone: app.checked.contains(e.id), kind: _kindOf(e.kind), icon: e.icon);

WeatherViewData? _tomorrowWeather(AppState app) {
  final w = app.weatherNextDay;
  if (w == null) return null;
  final now = app.screenNow;
  final day = DateTime(now.year, now.month, now.day + 1);
  final hours = [
    for (final h in app.weather?.hours ?? const <WeatherHour>[])
      if (h.at.year == day.year && h.at.month == day.month && h.at.day == day.day && h.at.hour >= 6 && h.at.hour % 3 == 0)
        WeatherHourViewData(label: hourText(h.at), temperature: h.tempC, rainChance: h.precipProb, icon: h.icon),
  ];
  return WeatherViewData(
    location: w.location,
    temperature: w.tempC.toDouble(),
    high: w.highC.toDouble(),
    low: w.lowC.toDouble(),
    condition: w.label,
    rainChance: w.precipProb,
    icon: w.icon,
    source: app.weatherAt == null ? null : _source(app.weatherAt!),
    hours: hours.take(4).toList(),
  );
}

/// null 이면 전류값을 보인다
String? _plugStatus(Appliance a) {
  if (onBoard && !simulatePlugs && shellyDirect.fresh(a.id)) {
    if (shellyDirect.output[a.id] != true) return '꺼짐';
    return a.isOn ? null : '켜짐 · 대기';
  }
  if (a.isOn) return null;
  if (!onBoard || simulatePlugs) return '꺼짐';
  // 노드가 꺼져 있으면 남은 retained 상태는 믿지 않는다
  if (!powerLink.nodeOnline) return '전력 노드 꺼짐';
  if (!powerLink.known(a.id)) return '연결 안 됨';
  return powerLink.state[a.id] == 'IDLE' ? '대기' : '꺼짐';
}

void _tapAppliance(String id) {
  if (ThinqSim.instance.byId(id) != null) {
    ThinqSim.instance.togglePower(id);
    return;
  }
  final a = app.appliances.where((a) => a.id == id).firstOrNull;
  if (a == null) return;
  app.plugOn(id) ? app.turnOff(id) : app.toggleAppliance(id);
}

CalendarViewData _calendar(AppState app, User user, List<CalendarEvent> events) => CalendarViewData(
      isLinked: user.calendarLinked,
      needsReauth: user.calendarNeedsReauth,
      loadFailed: app.calendarFailed,
      events: [for (final e in events) CalendarEventViewData(timeLabel: e.time, title: e.title)],
    );

GroupViewData? _group(AppState app) {
  if (!app.inGroup) return null;
  final things = app.groupThings;
  String nameOf(String id) => app.userOf(id)?.name ?? '';
  Color colorOf(String id) => app.userOf(id)?.color ?? const Color(0xFF8A90A6);
  return GroupViewData(
    memberIds: List.of(app.group),
    things: [
      for (final t in things)
        GroupThingViewData(
          name: t.name,
          icon: t.icon,
          common: t.common,
          done: t.done,
          reason: t.reason,
          waiting: [for (final w in t.waiting) (nameOf(w), colorOf(w))],
        ),
    ],
    total: things.fold(0, (n, t) => n + t.total),
    done: things.fold(0, (n, t) => n + t.doneCount),
    leftByPerson: [
      for (final id in app.group)
        if ([for (final t in things) if (t.waiting.contains(id)) t.name] case final names when names.isNotEmpty) (nameOf(id), colorOf(id), names),
    ],
  );
}

GroupPickViewData? _pick(AppState app, User me) => app.prompt != Prompt.groupPick
    ? null
    : GroupPickViewData(
        meName: me.name,
        meColor: me.color,
        candidates: [for (final u in app.groupCandidates) (u.id, u.name, u.color)],
        picked: Set.of(app.groupPick),
      );

class ChecklistPage extends StatelessWidget {
  const ChecklistPage({super.key});

  MemberState _stateOf(String id) {
    if (app.departed(id)) return MemberState.departed;
    if (app.returnedTodayAt(id) != null) return MemberState.returned;
    if (!app.engaged.contains(id)) return MemberState.notStarted;
    return app.readyOf(id) ? MemberState.ready : MemberState.pending;
  }

  // lastOut 확인은 출발 기록 뒤에 뜨므로 departed 보다 먼저 본다
  BarMode _barMode(String id) {
    if (app.prompt == Prompt.lastOut) return BarMode.lastOut;
    if (app.departed(id)) return BarMode.departed;
    return app.readyOf(id) ? BarMode.ready : BarMode.progress;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: ThinqSim.instance, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final app = watch(context);
    final user = app.user;
    if (user == null) return const SizedBox.shrink();
    final departedAt = app.departedAt[user.id];

    return ChecklistScreen(
      members: [
        for (final u in app.tabOrder)
          FamilyMemberViewData(
            id: u.id,
            name: u.name,
            color: u.color,
            state: _stateOf(u.id),
            remaining: app.remainingOf(u.id),
            departedLabel: app.departedAt[u.id] == null ? null : hhmm(app.departedAt[u.id]!),
            returnedLabel: app.returnedTodayAt(u.id) == null ? null : hhmm(app.returnedTodayAt(u.id)!),
          ),
      ],
      selectedId: user.id,
      userName: user.name,
      situation: app.situation,
      family: app.isFamily,
      familyTodos: _familyTodos(app),
      appliances: _appliances(app),
      weather: _weather(app),
      airLabel: app.air?.grade?.label,
      items: [
        for (final e in app.todayList) _item(app, e),
      ],
      tray: [for (final b in app.myBelongings) _trayItem(app, b)],
      onConfirmBelonging: app.acknowledgeBelonging,
      onPeekTray: app.openTrayPeek,
      calendar: _calendar(app, user, app.myEvents),
      barMode: _barMode(user.id),
      departedLabel: departedAt == null ? null : hhmm(departedAt),
      skipOpen: app.prompt == Prompt.skip,
      group: _group(app),
      pick: _pick(app, user),
      askEndGroup: app.prompt == Prompt.groupEnd,
      onStartGroup: app.isFamily && !app.inGroup && !app.departed(user.id) && app.groupCandidates.isNotEmpty ? app.openGroupPick : null,
      onTogglePick: app.toggleGroupPick,
      onConfirmPick: app.confirmGroupPick,
      onClosePrompt: app.closePrompt,
      onEndGroup: app.endGroup,
      // 모두 출발했으면 × 를 숨긴다
      onAskEndGroup: app.inGroup && !app.group.every(app.departed) ? app.askEndGroup : null,
      onTapGroupThing: app.tapGroupThing,
      memoPopup: app.morningMemosOf(user.id),
      onMemoSeen: app.seeMemos,
      // 함께 외출 중엔 가족을 누르면 묶음에 넣는다
      onSelectMember: app.inGroup ? app.addToGroup : app.switchUser,
      onSettings: () => app.openSettings(),
      onSituationTap: app.cycleSituation,
      onToggleFamilyTodo: app.toggleFamilyTodo,
      onTapAppliance: _tapAppliance,
      onLongPressAppliance: (id) => showApplianceSheet(context, id),
      onToggleItem: app.toggleCheck,
      onTakeTray: app.takeFromTray,
      onConnectCalendar: () => app.openSettings(SettingsPane.calendar, true),
      onRegisterBelongings: () => onBoard ? app.openTrayPeek() : app.openSettings(SettingsPane.belongings),
      onDepart: app.depart,
      onSkip: app.askSkip,
      onSkipConfirm: app.depart,
      onSkipCancel: app.closePrompt,
      onLastOutTurnOffAll: () => app.finishLastOut(turnOffAll: true),
      onLastOutLeave: () => app.finishLastOut(turnOffAll: false),
    );
  }
}

class ReturnPage extends StatelessWidget {
  const ReturnPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: ThinqSim.instance, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final app = watch(context);
    final user = app.user;
    if (user == null) return const SizedBox.shrink();
    return ReturnHomeScreen(
      members: [
        for (final u in app.tabOrder)
          FamilyMemberViewData(
            id: u.id,
            name: u.name,
            color: u.color,
            state: app.departed(u.id) ? MemberState.out : (app.returnedTodayAt(u.id) != null ? MemberState.returned : MemberState.home),
            remaining: 0,
            returnedLabel: app.returnedTodayAt(u.id) == null ? null : hhmm(app.returnedTodayAt(u.id)!),
          ),
      ],
      selectedId: user.id,
      userName: user.name,
      family: app.isFamily,
      familyTodos: _familyTodos(app),
      appliances: _appliances(app),
      weather: _weather(app),
      airLabel: app.air?.grade?.label,
      tomorrowWeatherData: _tomorrowWeather(app),
      tray: [for (final b in app.myBelongings) _trayItem(app, b)],
      returnedLabel: hhmm(app.returnedTodayAt(user.id) ?? app.screenNow),
      tomorrow: [for (final e in app.tomorrowListOf(user.id)) _item(app, e)],
      checkDone: app.returnCheckDone,
      leftOut: [for (final b in app.leftOutOf(user.id, daysAgo: 0)) b.name],
      check: !app.returnCheckOpen
          ? null
          : ReturnCheckViewData(
              items: [
                for (final b in app.myBelongings)
                  ReturnCheckItemViewData(id: b.id, name: b.name, icon: b.icon, checked: app.returnChecked.contains(b.id)),
              ],
              askLeftOut: app.returnAskLeftOut,
            ),
      calendar: _calendar(app, user, app.myRemainingEvents),
      done: app.returnDone,
      onSelectMember: app.switchUser,
      onSettings: () => app.openSettings(),
      onToggleFamilyTodo: app.toggleFamilyTodo,
      onTapAppliance: _tapAppliance,
      onLongPressAppliance: (id) => showApplianceSheet(context, id),
      onConnectCalendar: () => app.openSettings(SettingsPane.calendar, true),
      onFinish: app.finishReturn,
      onOpenCheck: app.openReturnCheck,
      onFinishCheck: app.finishBroughtBack,
      onAddTomorrow: () async {
        final lines = await (onBoard
            ? showVoiceMemo(context)
            : showTextEntry(context, title: '내일 챙길 것', hint: '예: 보조배터리', confirmLabel: '추가').then((n) => n == null ? null : [n]));
        for (final l in lines ?? const <String>[]) {
          app.addTomorrowNote(l);
        }
      },
      onRemoveTomorrow: app.removeTomorrowNote,
    );
  }
}
