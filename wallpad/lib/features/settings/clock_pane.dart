import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../core/config/app_clock.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/buttons.dart';
import 'settings_screen.dart';
import '../../shared/time_text.dart';

/// 시연용으로 앱 전체가 따르는 화면 시각을 옮긴다
class ClockPane extends StatefulWidget {
  const ClockPane({super.key});

  @override
  State<ClockPane> createState() => _ClockPaneState();
}

class _ClockPaneState extends State<ClockPane> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static (int, int) _hm(String? text, (int, int) fallback) {
    final m = parseMinutes(text);
    return m == null ? fallback : (m ~/ 60, m % 60);
  }

  void _shift(Duration d) => app.setScreenClock(AppClock.now().add(d));

  // 실제 오늘 기준
  void _jump(int days, (int, int) hm) {
    final real = DateTime.now();
    app.setScreenClock(DateTime(real.year, real.month, real.day + days, hm.$1, hm.$2));
  }

  @override
  Widget build(BuildContext context) {
    watch(context);
    final now = AppClock.now();
    final id = app.userId;
    final profile = id == null ? null : app.profiles[id];
    final leave = _hm(profile?.leaveTime, (7, 30)), back = _hm(profile?.returnTime, (19, 0));
    String hm((int, int) t) => minutesText(t.$1 * 60 + t.$2);
    final mode = id == null ? null : (app.returnTimeOf(id) ? '귀가' : app.outingWord);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(title: '화면 시각', subtitle: AppClock.shifted ? '실제 ${dateText(DateTime.now())} ${hhmm(DateTime.now())}' : '실제 시각'),
        const SizedBox(height: Space.l),
        Container(
          padding: const EdgeInsets.all(Space.xl),
          decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(dateText(now), style: Txt.sub),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(hhmm(now), style: Txt.title.copyWith(fontSize: 72, fontWeight: FontWeight.w300, fontFeatures: const [FontFeature.tabularFigures()])),
                  const SizedBox(width: Space.l),
                  if (mode != null)
                    Padding(padding: const EdgeInsets.only(bottom: 14), child: Text('${app.user?.name ?? ''}님 · $mode 화면', style: Txt.sub)),
                ],
              ),
              const SizedBox(height: Space.l),
              Row(
                children: [
                  Expanded(child: AppButton.ghost('오늘 출근 ${hm(leave)}', icon: Icons.wb_sunny_rounded, expand: true, onPressed: () => _jump(0, leave))),
                  const SizedBox(width: Space.s),
                  Expanded(child: AppButton.ghost('오늘 퇴근 ${hm(back)}', icon: Icons.nightlight_round, expand: true, onPressed: () => _jump(0, back))),
                ],
              ),
              const SizedBox(height: Space.s),
              Row(
                children: [
                  Expanded(child: AppButton.ghost('다음 날 출근 ${hm(leave)}', icon: Icons.wb_sunny_rounded, expand: true, onPressed: () => _jump(1, leave))),
                  const SizedBox(width: Space.s),
                  Expanded(child: AppButton.ghost('다음 날 퇴근 ${hm(back)}', icon: Icons.nightlight_round, expand: true, onPressed: () => _jump(1, back))),
                ],
              ),
              const SizedBox(height: Space.s),
              Row(
                children: [
                  for (final (label, d) in const [
                    ('−1일', Duration(days: -1)),
                    ('−1시간', Duration(hours: -1)),
                    ('−10분', Duration(minutes: -10)),
                    ('+10분', Duration(minutes: 10)),
                    ('+1시간', Duration(hours: 1)),
                    ('+1일', Duration(days: 1)),
                  ]) ...[
                    Expanded(child: AppButton.ghost(label, expand: true, onPressed: () => _shift(d))),
                    if (d != const Duration(days: 1)) const SizedBox(width: Space.s),
                  ],
                ],
              ),
              const SizedBox(height: Space.s),
              AppButton('실제 시각으로', expand: true, onPressed: AppClock.shifted ? () => app.setScreenClock(null) : null),
            ],
          ),
        ),
      ],
    );
  }
}
