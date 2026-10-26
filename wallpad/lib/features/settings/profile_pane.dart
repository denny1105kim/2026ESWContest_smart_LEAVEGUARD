import 'package:flutter/material.dart';

import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/card.dart';
import '../../shared/widgets/design_canvas.dart';
import '../../shared/widgets/swipe_adjust.dart';
import '../../core/data/models.dart' show MemberProfile, essentialCandidates, everyDayBits, weekdayBits;
import '../../app/app_state.dart';
import '../../core/theme/tokens.dart';
import 'settings_screen.dart';
import '../../shared/time_text.dart';

/// 온보딩에서 답한 생활 패턴을 보고 항목별로 고친다
class ProfilePane extends StatelessWidget {
  const ProfilePane({super.key});

  static const places = {'work': '회사 출근', 'home': '재택근무', 'school': '학교'};
  static const _placeIcons = {'work': Icons.work_outline_rounded, 'home': Icons.home_outlined, 'school': Icons.school_outlined};

  static const _defaultLeave = 8 * 60, _defaultReturn = 18 * 60 + 30;

  static String daysLabel(int days) {
    if (days == 0) return '없음';
    if (days == everyDayBits) return '매일';
    if (days == weekdayBits) return '월 – 금';
    return [for (var i = 0; i < 7; i++) if (days & (1 << i) != 0) weekdayNames[i]].join(' · ');
  }

  // 한 항목만 바꾸고 나머지는 그대로 둔다. 비어 있는 시간은 기본값으로
  static Future<void> _save(String id, {String? place, int? leave, int? back, int? days}) async {
    final old = app.profiles[id];
    final p = place ?? old?.weekdayPlace;
    final fixed = p != 'home';
    await app.saveProfile(
      id,
      MemberProfile(
        weekdayPlace: p,
        scheduleMode: p == null ? old?.scheduleMode : (fixed ? 'fixed' : 'none'),
        leaveTime: fixed ? minutesText(leave ?? parseMinutes(old?.leaveTime) ?? _defaultLeave) : null,
        returnTime: fixed ? minutesText(back ?? parseMinutes(old?.returnTime) ?? _defaultReturn) : null,
        days: fixed ? (days ?? old?.days ?? weekdayBits) : null,
        remindBefore: fixed ? (old?.remindBefore ?? 20) : null,
        transport: old?.transport,
        weekend: old?.weekend,
      ),
    );
  }

  // 취소하면 null
  static Future<T?> _edit<T>(BuildContext context, String title, T initial, Widget Function(T value, ValueChanged<T> set) body) {
    return showDialog<T>(
      context: context,
      barrierColor: const Color(0xFF101322).withValues(alpha: 0.55),
      builder: (context) => DesignCanvas.legacy(child: _EditDialog<T>(title: title, initial: initial, body: body)),
    );
  }

  @override
  Widget build(BuildContext context) {
    watch(context);
    final user = app.user;
    if (user == null) return const EmptyNote(icon: Icons.person_off_rounded, text: '로그인한 사용자가 없어요');
    final id = user.id;
    final p = app.profiles[id];
    final place = p?.weekdayPlace;
    final leave = parseMinutes(p?.leaveTime) ?? _defaultLeave;
    final back = parseMinutes(p?.returnTime) ?? _defaultReturn;
    final days = p?.days ?? weekdayBits;
    final mine = app.essentials[id] ?? const <String>[];
    final home = place == 'home';

    Future<void> editPlace() async {
      final v = await _edit<String?>(
        context,
        '근무 형태',
        place,
        (v, set) => Column(
          children: [
            for (final e in places.entries) ...[
              _Choice(icon: _placeIcons[e.key], label: e.value, on: v == e.key, onTap: () => set(e.key), height: 60),
              const SizedBox(height: Space.s),
            ],
          ],
        ),
      );
      if (v != null) await _save(id, place: v);
    }

    Future<void> editTime(String title, int now, bool isLeave) async {
      final v = await _edit<int>(context, title, now, (v, set) => _SwipeTime(minutes: v, onChanged: set));
      if (v != null) await (isLeave ? _save(id, leave: v) : _save(id, back: v));
    }

    Future<void> editDays() async {
      final v = await _edit<int>(
        context,
        '요일',
        days,
        (v, set) => Row(
          children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: Space.s),
              Expanded(child: _Choice(label: weekdayNames[i], on: v & (1 << i) != 0, onTap: () => set(v ^ (1 << i)), height: 56)),
            ],
          ],
        ),
      );
      if (v != null) await _save(id, days: v);
    }

    Future<void> editEssentials() async {
      final all = [...essentialCandidates, for (final n in mine) if (!essentialCandidates.contains(n)) n];
      final v = await _edit<Set<String>>(
        context,
        '꼭 챙길 것',
        mine.toSet(),
        (v, set) => Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final n in all)
              SizedBox(
                width: 116,
                child: _Choice(label: n, on: v.contains(n), onTap: () => set(v.contains(n) ? ({...v}..remove(n)) : {...v, n})),
              ),
          ],
        ),
      );
      if (v != null) await app.setEssentials(id, [for (final n in all) if (v.contains(n)) n]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PaneHeader(title: '생활 패턴'),
        const SizedBox(height: Space.l),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _GroupTitle('외출'),
                _Group(rows: [
                  _Row(label: '근무 형태', value: places[place] ?? '정하지 않음', onTap: editPlace),
                  if (!home) ...[
                    _Row(label: '집을 나서는 시간', value: minutesText(leave), onTap: () => editTime('집을 나서는 시간', leave, true)),
                    _Row(label: '돌아오는 시간', value: minutesText(back), onTap: () => editTime('돌아오는 시간', back, false)),
                    _Row(label: '요일', value: daysLabel(days), onTap: editDays),
                  ],
                ]),
                const SizedBox(height: Space.xl),
                const _GroupTitle('소지품'),
                _Group(rows: [
                  _Row(label: '꼭 챙길 것', value: mine.isEmpty ? '없음' : mine.join(' · '), onTap: editEssentials),
                ]),
                const SizedBox(height: Space.l),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupTitle extends StatelessWidget {
  final String text;

  const _GroupTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: Space.s, bottom: Space.s),
      child: Text(text, style: Txt.section.copyWith(color: Palette.muted)),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> rows;

  const _Group({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card - 4), boxShadow: Shadows.card),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: Palette.line),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final VoidCallback onTap;

  const _Row({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.only(left: Space.xl, right: Space.l),
          child: Row(
            children: [
              Text(label, style: Txt.body.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(width: Space.l),
              Expanded(child: Text(value, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: Txt.body.copyWith(color: Palette.muted))),
              const SizedBox(width: Space.s),
              const Icon(Icons.chevron_right_rounded, size: 26, color: Palette.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditDialog<T> extends StatefulWidget {
  final String title;
  final T initial;
  final Widget Function(T value, ValueChanged<T> set) body;

  const _EditDialog({super.key, required this.title, required this.initial, required this.body});

  @override
  State<_EditDialog<T>> createState() => _EditDialogState<T>();
}

class _EditDialogState<T> extends State<_EditDialog<T>> {
  late T _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Palette.dialog,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xxl, 28, Space.xxl, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Txt.title.copyWith(fontSize: 24)),
              const SizedBox(height: Space.xl),
              widget.body(_value, (v) => setState(() => _value = v)),
              const SizedBox(height: Space.xl),
              Row(
                children: [
                  Expanded(child: AppButton.ghost('취소', expand: true, onPressed: () => Navigator.pop(context))),
                  const SizedBox(width: Space.m),
                  Expanded(child: AppButton('저장', expand: true, onPressed: () => Navigator.pop(context, _value))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  final double height;

  const _Choice({this.icon, required this.label, required this.on, required this.onTap, this.height = 52});

  @override
  Widget build(BuildContext context) {
    final color = on ? Palette.accent : Palette.muted;
    return Material(
      color: on ? Palette.accent.withValues(alpha: 0.1) : Palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.button),
        side: BorderSide(color: on ? Palette.accent : Palette.line, width: on ? 2 : 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 22, color: color), const SizedBox(width: Space.s)],
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Txt.bodyStrong.copyWith(color: on ? Palette.accent : Palette.text))),
            ],
          ),
        ),
      ),
    );
  }
}

/// 좌우로 밀거나 양옆 값을 눌러 10분씩 바꾸는 시각 선택
class _SwipeTime extends StatefulWidget {
  final int minutes;
  final ValueChanged<int> onChanged;

  const _SwipeTime({required this.minutes, required this.onChanged});

  @override
  State<_SwipeTime> createState() => _SwipeTimeState();
}

class _SwipeTimeState extends State<_SwipeTime> with SingleTickerProviderStateMixin {
  late final AnimationController _nudge;

  @override
  void initState() {
    super.initState();
    _nudge = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _nudge.repeat(count: 3);
    });
  }

  @override
  void dispose() {
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.minutes;
    Widget side(int delta) => Expanded(
          child: InkWell(
            onTap: () => widget.onChanged((m + delta + 1440) % 1440),
            borderRadius: BorderRadius.circular(Radii.button),
            child: SizedBox(
              height: 96,
              child: Center(child: Text(minutesText(m + delta), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Palette.faint))),
            ),
          ),
        );
    Widget arrow(bool left) => AnimatedBuilder(
          animation: _nudge,
          builder: (_, child) => Transform.translate(offset: Offset((left ? -6 : 6) * Curves.easeInOut.transform(1 - (2 * _nudge.value - 1).abs()), 0), child: child),
          child: Icon(left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 34, color: Palette.accent),
        );
    return Listener(
      onPointerDown: (_) => _nudge.stop(),
      child: SwipeAdjust(
        value: m,
        wrap: 1440,
        onChanged: widget.onChanged,
        child: Container(
          height: 96,
          decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(Radii.button)),
          child: Row(
            children: [
              side(-10),
              arrow(true),
              Container(
                width: 150,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Palette.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Palette.accent, width: 2),
                ),
                child: Text(minutesText(m), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Palette.text)),
              ),
              arrow(false),
              side(10),
            ],
          ),
        ),
      ),
    );
  }
}
