part of 'checklist_screen.dart';

/// 귀가 화면. 출근 화면과 같은 틀과 부품을 쓴다
class ReturnHomeScreen extends StatelessWidget {
  const ReturnHomeScreen({
    super.key,
    required this.members,
    required this.selectedId,
    required this.userName,
    this.family = true,
    required this.familyTodos,
    required this.appliances,
    required this.weather,
    this.airLabel,
    this.tomorrowWeatherData,
    this.tray = const [],
    this.returnedLabel,
    required this.tomorrow,
    this.checkDone = false,
    this.leftOut = const [],
    this.check,
    required this.calendar,
    this.done = false,
    required this.onSelectMember,
    required this.onSettings,
    required this.onToggleFamilyTodo,
    this.onTapAppliance,
    this.onLongPressAppliance,
    required this.onConnectCalendar,
    required this.onFinish,
    required this.onOpenCheck,
    required this.onFinishCheck,
    required this.onAddTomorrow,
    required this.onRemoveTomorrow,
  });

  final List<FamilyMemberViewData> members;
  final String selectedId;
  final String userName;
  final bool family;
  final List<FamilyTodoViewData> familyTodos;
  final List<ApplianceViewData> appliances;
  final WeatherViewData weather;
  final String? airLabel;

  /// null 이면 오늘 날씨를 보인다
  final WeatherViewData? tomorrowWeatherData;
  final List<TrayItemViewData> tray;
  final String? returnedLabel;
  final List<ChecklistItemViewData> tomorrow;
  final bool checkDone;
  final List<String> leftOut;
  final ReturnCheckViewData? check;
  final CalendarViewData calendar;
  final bool done;

  final ValueChanged<String> onSelectMember;
  final VoidCallback onSettings;
  final ValueChanged<String> onToggleFamilyTodo;
  final ValueChanged<String>? onTapAppliance;
  final ValueChanged<String>? onLongPressAppliance;
  final VoidCallback onConnectCalendar;
  final VoidCallback onFinish;
  final VoidCallback onOpenCheck;

  /// 두고 온 것의 id (비었으면 모두 챙겨 옴)
  final ValueChanged<Set<String>> onFinishCheck;
  final VoidCallback onAddTomorrow;
  final ValueChanged<String> onRemoveTomorrow;

  @override
  Widget build(BuildContext context) {
    final check = this.check;
    final (things, extra, back) = _things();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _Dashboard(
            topRow: _TopRow(members: members, selectedId: selectedId, family: family, onSelectMember: onSelectMember, onSettings: onSettings),
            hero: _Hero(greeting: 'Welcome\nHome!', lines: [_headline, _summary]),
            upper: _UpperCard(
              calendarTitle: '주요 일정',
              calendar: calendar,
              emptyText: '일정 없음',
              onConnect: onConnectCalendar,
              family: family,
              todos: familyTodos,
              onToggleTodo: onToggleFamilyTodo,
              weatherTitle: tomorrowWeatherData == null ? '날씨' : '내일 날씨',
              weather: tomorrowWeatherData ?? weather,
              airLabel: airLabel,
              single: true,
            ),
            lower: _LowerCard(
              title: '소지품 List',
              count: _takenToday.isEmpty ? '' : '챙겨 옴 $back / ${_takenToday.length}',
              things: things,
              extra: extra,
              appliances: appliances,
              onTap: onTapAppliance,
              onLongPress: onLongPressAppliance,
            ),
            side: _side(),
          ),
          if (check != null)
            Positioned.fill(
              child: _BroughtBackPopup(items: _takenToday, checked: {for (final i in check.items) if (i.checked) i.id}, onDone: onFinishCheck),
            ),
        ],
      ),
    );
  }

  List<TrayItemViewData> get _takenToday => [for (final t in tray) if (t.takenToday) t];

  /// (보일 칸, 숨은 칸 수, 챙겨 온 것 수)
  (List<_Thing>, int, int) _things() {
    const broughtBack = '챙겨 옴';
    _Thing thing(TrayItemViewData t) {
      if (leftOut.contains(t.name)) return _Thing(name: t.name, sub: '안 챙겨 옴', subColor: _D.orange, icon: t.icon, onTap: onOpenCheck);
      return switch (t.state) {
        TrayState.onTray when t.takenToday => _Thing(name: t.name, sub: broughtBack, subColor: _D.green, icon: t.icon, onTap: onOpenCheck),
        TrayState.taken || TrayState.notReturned when checkDone && t.takenToday =>
          _Thing(name: t.name, sub: broughtBack, subColor: _D.green, icon: t.icon, onTap: onOpenCheck),
        TrayState.onTray => _Thing(name: t.name, sub: '트레이에 있음', icon: t.icon, dim: true),
        TrayState.notReturned when !t.takenToday => _Thing(name: t.name, sub: _awayText(t), subColor: _D.orange, icon: t.icon, onTap: onOpenCheck),
        TrayState.takenByOther => _Thing(name: t.name, sub: t.backDetail ?? '가족이 가짐', icon: t.icon, dim: true, onTap: onOpenCheck),
        TrayState.unknown => _Thing(name: t.name, sub: '카메라 끊김 · 미확인', icon: t.icon, dim: true),
        _ => _Thing(name: t.name, sub: t.backDetail ?? '오늘 가져감', icon: t.icon, onTap: onOpenCheck),
      };
    }

    final all = [for (final t in tray) thing(t)];
    final shown = all.take(7).toList();
    return (
      [...shown, _Thing(name: '내일 메모', sub: '', icon: Icons.add_rounded, dim: true, onTap: onAddTomorrow)],
      all.length - shown.length,
      all.where((t) => t.sub == broughtBack).length,
    );
  }

  List<String> get _forecastItems => [for (final i in tomorrow) if (i.kind != ChecklistItemKind.leftOut) i.title];

  String get _headline => '$userName님';

  String get _summary {
    final forecast = _forecastItems;
    final familyLeft = familyTodos.where((t) => !t.isDone).length;
    return [
      if (leftOut.isNotEmpty) '두고 옴 · ${leftOut.join(' · ')}',
      if (forecast.isNotEmpty) '내일 · ${forecast.join(' · ')}',
      if (family && familyLeft > 0) '가족 할 일 $familyLeft개',
      '',
    ].first;
  }

  Widget _side() {
    if (done) {
      return _SideNotice(title: '귀가', icon: Icons.bedtime_rounded, color: _D.soft, headline: '완료', detail: '');
    }
    // 두고 온 것, 직접 적은 것, 날씨 순
    final ordered = [
      ...tomorrow.where((i) => i.kind == ChecklistItemKind.leftOut),
      ...tomorrow.where((i) => i.kind == ChecklistItemKind.note),
      ...tomorrow.where((i) => i.kind != ChecklistItemKind.leftOut && i.kind != ChecklistItemKind.note),
    ];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head('귀가', trailing: returnedLabel == null ? null : '$returnedLabel 도착'),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${ordered.length}', style: _D.t(120, w: FontWeight.w200, h: 1, ls: -2)),
              const SizedBox(width: 10),
              Text('개', style: _D.t(34, w: FontWeight.w300, c: _D.faint)),
            ],
          ),
          const SizedBox(height: 10),
          Text('내일 챙길 것', style: _D.t(22, w: FontWeight.w600)),
          const SizedBox(height: 14),
          SizedBox(
            height: 92,
            child: ordered.isEmpty
                ? Text('없음', style: _D.t(16, c: _D.faint))
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    clipBehavior: Clip.hardEdge,
                    children: [for (final i in ordered.take(6)) _tomorrowChip(i)],
                  ),
          ),
          const Spacer(),
          _WhiteButton(label: '다 했어요', icon: Icons.home_rounded, onPressed: onFinish),
        ],
      ),
    );
  }

  Widget _tomorrowChip(ChecklistItemViewData i) {
    final left = i.kind == ChecklistItemKind.leftOut;
    final note = i.kind == ChecklistItemKind.note;
    final chip = Container(
      height: 40,
      padding: EdgeInsets.only(left: 16, right: note ? 10 : 16),
      decoration: BoxDecoration(color: left ? _D.orange.withValues(alpha: 0.22) : const Color(0x24FFFFFF), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(i.title, style: _D.t(16, w: FontWeight.w600, c: left ? _D.orange : Colors.white, h: 1)),
          if (note) ...[const SizedBox(width: 6), const Icon(Icons.close_rounded, size: 18, color: _D.faint)],
        ],
      ),
    );
    if (!note) return chip;
    return Semantics(button: true, label: '${i.title} 지우기', child: GestureDetector(onTap: () => onRemoveTomorrow(i.id), child: chip));
  }

  static String _awayText(TrayItemViewData t) => switch (t.daysAway) {
        1 => '어제부터 없음',
        > 1 => '${t.daysAway}일째 없음',
        _ => t.backDetail ?? t.detail ?? '없음',
      };
}

/// 오늘 가져간 것 중 챙겨 온 것을 짚게 한다. 안 짚은 것은 두고 온 것으로 묻는다
class _BroughtBackPopup extends StatefulWidget {
  const _BroughtBackPopup({required this.items, required this.checked, required this.onDone});

  final List<TrayItemViewData> items;
  final Set<String> checked;

  /// 안 누른 칸 (두고 온 것)
  final ValueChanged<Set<String>> onDone;

  @override
  State<_BroughtBackPopup> createState() => _BroughtBackPopupState();
}

class _BroughtBackPopupState extends State<_BroughtBackPopup> {
  static const _width = 1000.0;
  static const _gap = 18.0;
  static const _green = Color(0xFF22A06B);

  late final _checked = {...widget.checked};
  var _asking = false;

  Set<String> get _left => {for (final t in widget.items) if (!_checked.contains(t.id)) t.id};

  void _confirm() => _left.isEmpty ? widget.onDone(const {}) : setState(() => _asking = true);

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final tileWidth = (_width - 2 * 48 - 2 * _gap) / 3;
    // 안 보이는 칸이 두고 온 것으로 처리되지 않게 줄이 많으면 칸을 낮춘다
    final rows = (items.length / 3).ceil();
    final tileHeight = rows <= 2 ? 190.0 : max(96.0, (2 * 190 + _gap - (rows - 1) * _gap) / rows);
    return Container(
      color: const Color(0x99101322),
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: WallpadTokens.modalTransition,
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(opacity: t, child: Transform.scale(scale: 0.96 + 0.04 * t, child: child)),
        child: Container(
          width: _width,
          padding: const EdgeInsets.fromLTRB(48, 44, 48, 44),
          decoration: BoxDecoration(
            color: WallpadTokens.surfaceSolid,
            borderRadius: BorderRadius.circular(36),
            boxShadow: const [BoxShadow(color: Color(0x66101322), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: const Color(0x24FFFFFF), borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Icons.inventory_2_outlined, size: 32, color: Colors.white),
                  ),
                  const SizedBox(width: 20),
                  Text(_asking ? '두고 오셨어요?' : '챙겨오셨나요?', style: _D.t(34, w: FontWeight.w700, h: 1.2)),
                ],
              ),
              const SizedBox(height: 36),
              if (_asking) ...[
                Text([for (final t in items) if (_left.contains(t.id)) t.name].join(' · '), style: _D.t(30, w: FontWeight.w600)),
                const SizedBox(height: 12),
                Text('내일 아침 외출 화면에 "어제 밖에 두고 왔어요"로 알려 드려요', style: _D.t(20, c: _D.faint)),
                const SizedBox(height: 36),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(width: 220, child: _SoftButton(label: '다시 볼게요', onPressed: () => setState(() => _asking = false))),
                    const SizedBox(width: 16),
                    SizedBox(width: 280, child: _WhiteButton(label: '네, 두고 왔어요', onPressed: () => widget.onDone(_left), height: 72)),
                  ],
                ),
              ] else
                Wrap(
                  spacing: _gap,
                  runSpacing: _gap,
                  children: [for (final t in items) SizedBox(width: tileWidth, height: tileHeight, child: _tile(t, compact: rows > 2))],
                ),
              if (!_asking) ...[
                const SizedBox(height: 28),
                Align(alignment: Alignment.centerRight, child: SizedBox(width: 240, child: _WhiteButton(label: '확인', onPressed: _confirm, height: 72))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(TrayItemViewData t, {bool compact = false}) {
    final on = _checked.contains(t.id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => on ? _checked.remove(t.id) : _checked.add(t.id)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: compact ? const EdgeInsets.fromLTRB(22, 14, 18, 14) : const EdgeInsets.fromLTRB(26, 24, 22, 24),
        decoration: BoxDecoration(
          color: on ? const Color(0x3322A06B) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: on ? _green : Colors.transparent, width: 3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(t.icon, size: compact ? 30 : 38, color: Colors.white),
            const Spacer(),
            Text(t.name, style: _D.t(compact ? 24 : 32, w: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (!compact) ...[
              const SizedBox(height: 6),
              Text(on ? '챙겨 옴' : (t.backDetail ?? '오늘 가져감'), style: _D.t(18, c: on ? const Color(0xFF7EE2B0) : const Color(0xCCFFFFFF)), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}
