part of '../checklist_screen.dart';

class _UpperCard extends StatelessWidget {
  const _UpperCard({
    required this.calendarTitle,
    required this.calendar,
    required this.emptyText,
    required this.onConnect,
    required this.family,
    required this.todos,
    required this.onToggleTodo,
    required this.weatherTitle,
    required this.weather,
    this.airLabel,
    this.single = false,
  });

  final String calendarTitle;
  final CalendarViewData calendar;
  final String emptyText;
  final VoidCallback onConnect;
  final bool family;
  final List<FamilyTodoViewData> todos;
  final ValueChanged<String> onToggleTodo;
  final String weatherTitle;
  final WeatherViewData weather;
  final String? airLabel;

  /// 목록 대신 가장 가까운 일정 하나만 크게
  final bool single;

  static const _rows = 4;

  @override
  Widget build(BuildContext context) {
    final now = AppClock.now();
    final events = calendar.events;
    final familyTodos = family ? todos : const <FamilyTodoViewData>[];
    // 일정 먼저, 남는 줄에 가족 할 일
    final shownEvents = events.take(_rows).toList();
    final shownTodos = familyTodos.take(_rows - shownEvents.length).toList();
    final extra = events.length + familyTodos.length - shownEvents.length - shownTodos.length;
    return _Panel(
      padding: const EdgeInsets.fromLTRB(32, 28, 28, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Head(calendarTitle, trailing: single ? (events.length > 1 ? '외 ${events.length - 1}건' : null) : extra > 0 ? '외 $extra건' : '${now.month}월 ${now.day}일'),
                const SizedBox(height: 10),
                Expanded(
                  child: single
                      ? (events.isEmpty ? _empty() : _KeyEventCard(event: events.first, sub: _until(events.first.timeLabel)))
                      : shownEvents.isEmpty && shownTodos.isEmpty
                      ? _empty()
                      : Column(
                          children: [
                            for (var i = 0; i < shownEvents.length; i++)
                              _ScheduleRow(
                                color: _colors[i % _colors.length],
                                time: shownEvents[i].timeLabel,
                                title: shownEvents[i].title,
                                sub: _until(shownEvents[i].timeLabel),
                                divider: i > 0,
                              ),
                            for (var i = 0; i < shownTodos.length; i++)
                              _ScheduleRow(
                                color: shownTodos[i].isDone ? _D.green : _D.faint,
                                time: shownTodos[i].timeLabel,
                                title: '가족 · ${shownTodos[i].name}',
                                sub: shownTodos[i].isDone ? '완료${shownTodos[i].doneBy == null ? '' : ' · ${shownTodos[i].doneBy}'}' : null,
                                done: shownTodos[i].isDone,
                                divider: shownEvents.isNotEmpty || i > 0,
                                onTap: () => onToggleTodo(shownTodos[i].id),
                              ),
                            const Spacer(),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          SizedBox(width: 484, child: _WeatherPanel(title: weatherTitle, data: weather, airLabel: airLabel)),
        ],
      ),
    );
  }

  static const _colors = [Color(0xFF4C6FFF), Color(0xFFE5484D), Color(0xFFE88A24), Color(0xFF22A06B)];

  /// 라벨에 시각이 없으면 null
  static String? _until(String label) {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(label);
    if (m == null) return null;
    final now = AppClock.now();
    final at = DateTime(now.year, now.month, now.day, int.parse(m[1]!), int.parse(m[2]!));
    final d = at.difference(now);
    if (d.isNegative) return '지난 일정';
    final h = d.inHours, mm = d.inMinutes % 60;
    return '${h > 0 ? '$h시간 ' : ''}$mm분 뒤';
  }

  Widget _empty() {
    final needLink = !calendar.isLinked || calendar.needsReauth;
    final text = !calendar.isLinked
        ? '캘린더 미연동'
        : calendar.needsReauth
            ? '연동 만료'
            : calendar.loadFailed
                ? '불러오기 실패'
                : emptyText;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(needLink ? Icons.event_busy_rounded : Icons.event_available_rounded, size: 40, color: _D.faint),
          const SizedBox(height: 12),
          Text(text, style: _D.t(19, c: _D.faint)),
          if (needLink) ...[const SizedBox(height: 8), Row(mainAxisSize: MainAxisSize.min, children: [_Pill(calendar.isLinked ? '다시 연동' : '연동하기', color: WallpadTokens.ink, background: Colors.white, onTap: onConnect)])],
        ],
      ),
    );
  }
}

class _KeyEventCard extends StatelessWidget {
  const _KeyEventCard({required this.event, this.sub});

  final CalendarEventViewData event;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4D428A), Color(0xFF39437A)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x998C8CF0), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: const Color(0x24FFFFFF), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.event_rounded, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.timeLabel, style: _D.t(22, w: FontWeight.w600, c: const Color(0xE6FFFFFF))),
                    const SizedBox(height: 4),
                    Text(event.title, style: _D.t(44, w: FontWeight.w700, h: 1.15), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          if (sub != null)
            Row(children: [
              const Icon(Icons.schedule_rounded, size: 20, color: _D.faint),
              const SizedBox(width: 8),
              Text(sub!, style: _D.t(19, c: const Color(0xCCFFFFFF))),
            ]),
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.color, required this.time, required this.title, this.sub, this.divider = false, this.done = false, this.onTap});

  final Color color;
  final String time, title;
  final String? sub;
  final bool divider, done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 75,
        decoration: BoxDecoration(border: divider ? const Border(top: BorderSide(color: _D.line)) : null),
        child: Row(
          children: [
            Container(width: 4, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 20),
            SizedBox(width: 76, child: Text(time, style: _D.t(19, w: FontWeight.w300, c: const Color(0xCCFFFFFF)), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _D.t(21, w: FontWeight.w600, c: done ? _D.faint : Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (sub != null) Text(sub!, style: _D.t(14, c: _D.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 기상청 출처 표시는 공공누리 조건이라 빼면 안 된다
class _WeatherPanel extends StatelessWidget {
  const _WeatherPanel({required this.title, required this.data, this.airLabel});

  final String title;
  final WeatherViewData data;
  final String? airLabel;

  @override
  Widget build(BuildContext context) {
    final hours = data.hours.take(4).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
      decoration: BoxDecoration(color: _D.panel, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(title, style: _D.t(22, w: FontWeight.w600)),
              const Spacer(),
              if (airLabel != null) Text('미세먼지 $airLabel', style: _D.t(15, c: _D.faint)),
            ],
          ),
          if (data.notice != null)
            Expanded(child: Center(child: Text(data.notice!, style: _D.t(19, c: _D.faint), textAlign: TextAlign.center)))
          else ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(data.icon ?? Icons.wb_cloudy_rounded, size: 52, color: Colors.white),
                const SizedBox(width: 14),
                Text('${data.temperature.round()}°', style: _D.t(66, w: FontWeight.w200, h: 1)),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data.condition, style: _D.t(20, w: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('최고 ${data.high.round()}° · 최저 ${data.low.round()}° · 강수 ${data.rainChance}%', style: _D.t(14, c: _D.faint), maxLines: 1),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (hours.length >= 2)
              Expanded(child: _HourlyGraph(hours: hours))
            else
              const Spacer(),
            if (data.source != null) Align(alignment: Alignment.centerRight, child: Text(data.source!, style: _D.t(12, c: _D.dim))),
          ],
        ],
      ),
    );
  }
}

class _HourlyGraph extends StatelessWidget {
  const _HourlyGraph({required this.hours});

  final List<WeatherHourViewData> hours;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (final h in hours)
              Expanded(
                child: Column(
                  children: [
                    Text(h.label, style: _D.t(14, c: _D.faint)),
                    const SizedBox(height: 6),
                    Icon(h.icon, size: 26, color: Colors.white),
                    const SizedBox(height: 6),
                    Text('${h.temperature}°', style: _D.t(20, w: FontWeight.w600, h: 1.1)),
                    Text('${h.rainChance}%', style: _D.t(13, w: FontWeight.w600, c: _D.soft)),
                  ],
                ),
              ),
          ],
        ),
        Expanded(child: CustomPaint(size: Size.infinite, painter: _CurvePainter([for (final h in hours) h.temperature.toDouble()]))),
      ],
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.height < 16) return;
    final lo = values.reduce(min), hi = values.reduce(max);
    final span = (hi - lo).abs() < 1 ? 1.0 : hi - lo;
    final step = size.width / values.length;
    final top = 10.0, bottom = size.height - 10;
    final pts = [
      for (var i = 0; i < values.length; i++) Offset(step * (i + 0.5), bottom - (values[i] - lo) / span * (bottom - top)),
    ];
    // 양 끝은 판 가장자리까지 평평하게 잇는다
    final all = [Offset(0, pts.first.dy), ...pts, Offset(size.width, pts.last.dy)];
    final path = Path()..moveTo(all.first.dx, all.first.dy);
    for (var i = 1; i < all.length; i++) {
      final a = all[i - 1], b = all[i];
      final mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = _D.soft,
    );
    for (final p in pts) {
      canvas.drawCircle(p, 5, Paint()..color = _D.soft);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.values.join(',') != values.join(',');
}
