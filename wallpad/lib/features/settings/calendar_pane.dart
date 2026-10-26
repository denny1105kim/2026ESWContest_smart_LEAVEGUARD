import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/card.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/qr_panel.dart';
import '../../shared/widgets/tags.dart';
import '../../app/app_state.dart';
import '../../core/theme/tokens.dart';
import 'settings_screen.dart';
import '../../shared/time_text.dart';

class CalendarPane extends StatefulWidget {
  const CalendarPane({super.key});

  @override
  State<CalendarPane> createState() => _CalendarPaneState();
}

class _CalendarPaneState extends State<CalendarPane> {
  Timer? _tick;
  late bool _wasConnected = _connected;
  var _justConnected = false;

  bool get _connected => app.user?.calendarLinked == true && app.user?.calendarNeedsReauth != true;

  Duration? get _left {
    final end = app.calendarLinkExpires;
    if (end == null) return null;
    final d = end.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    // initState 안에서 notifyListeners 가 나가면 화면 갱신이 멈춘다. 첫 프레임 뒤에 시작
    if (!_connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_connected) _startQr();
      });
    }
    app.addListener(_onApp);
  }

  @override
  void dispose() {
    _tick?.cancel();
    app.removeListener(_onApp);
    app.stopCalendarQr();
    super.dispose();
  }

  void _startQr() {
    _tick?.cancel();
    app.newCalendarQr();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  void _onApp() {
    if (!mounted) return;
    if (_connected && !_wasConnected) {
      _wasConnected = true;
      _tick?.cancel();
      setState(() => _justConnected = true);
      Timer(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        setState(() => _justConnected = false);
        if (app.calendarFromChecklist) app.go(Stage.checklist);
      });
    } else if (!_connected && _wasConnected) {
      _wasConnected = false;
      _startQr();
    }
  }

  @override
  Widget build(BuildContext context) {
    watch(context);
    return Stack(
      children: [
        _connected ? _connectedView(context) : _qrView(),
        if (_justConnected) const _ConnectedFlash(),
      ],
    );
  }

  Widget _qrView() {
    final url = app.calendarLinkUrl, error = app.calendarError, left = _left;
    final expired = left != null && left <= Duration.zero;
    final reauth = app.user?.calendarNeedsReauth == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(title: '캘린더 연동', subtitle: reauth ? '연결이 만료됐어요. QR 을 다시 찍어 주세요' : null),
        const SizedBox(height: Space.xl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                if (url != null)
                  QrPanel(data: url, size: 232, expired: expired || error != null)
                else
                  SizedBox.square(
                    dimension: 232,
                    child: Center(
                      child: error != null
                          ? const Icon(Icons.cloud_off_rounded, size: 56, color: Palette.faint)
                          : const CircularProgressIndicator(color: Palette.accent),
                    ),
                  ),
                const SizedBox(height: Space.s),
                if (error != null)
                  SizedBox(width: 232, child: Text(error, textAlign: TextAlign.center, style: Txt.caption.copyWith(color: Palette.pending))),
                const SizedBox(height: Space.s),
                if (expired || error != null)
                  AppButton.ghost('새 QR 만들기', icon: Icons.refresh_rounded, onPressed: _startQr)
                else if (left != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 18, color: Palette.faint),
                      const SizedBox(width: 6),
                      Text('${mmss(left)} 후 만료', style: Txt.caption),
                    ],
                  ),
              ],
            ),
            const SizedBox(width: Space.xxl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('휴대폰으로 스캔하세요', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Palette.text)),
                  const SizedBox(height: Space.l),
                  const _StepLine(1, '휴대폰 카메라로 QR을 찍어요'),
                  const _StepLine(2, '구글 계정으로 로그인하고 허용해요'),
                  const _StepLine(3, '연동되면 여기가 저절로 바뀌어요'),
                  const SizedBox(height: Space.m),
                  Container(
                    padding: const EdgeInsets.all(Space.m + 2),
                    decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.button), boxShadow: Shadows.card),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.help_outline_rounded, size: 20, color: Palette.muted),
                        SizedBox(width: Space.s),
                        Expanded(
                          child: Text('캘린더는 읽기만 해요\n연동을 끊으면 서버에 저장된 구글 연결도 지워져요', style: TextStyle(fontSize: 15, color: Palette.muted, height: 1.4)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _connectedView(BuildContext context) {
    final events = app.myEvents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PaneHeader(title: '캘린더 연동'),
        const SizedBox(height: Space.xl),
        Container(
          padding: const EdgeInsets.all(Space.l + 4),
          decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.card),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: Palette.soft(Palette.done), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.event_available_rounded, color: Palette.done, size: 28),
              ),
              const SizedBox(width: Space.l),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('구글 캘린더', style: Txt.bodyStrong),
                    Text('구글 계정 연결됨 · 읽기 전용', style: Txt.caption),
                  ],
                ),
              ),
              const StatusTag('연동됨', color: Palette.done, icon: Icons.check_rounded),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        SectionCard(
          title: '오늘 일정 미리보기',
          icon: Icons.event_rounded,
          child: events.isEmpty
              ? const EmptyNote(icon: Icons.event_available_rounded, text: '오늘 일정이 없어요')
              : Column(
                  children: [
                    for (final e in events.take(3))
                      SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            SizedBox(width: 68, child: Text(e.time, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Palette.accent))),
                            Text(e.title, style: Txt.body),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const Spacer(),
        if (app.calendarError != null) ...[
          Text(app.calendarError!, style: Txt.caption.copyWith(color: Palette.pending)),
          const SizedBox(height: Space.s),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            '연동 해제',
            icon: Icons.link_off_rounded,
            tone: ButtonTone.outline,
            onPressed: () async {
              final ok = await confirmDelete(context, title: '캘린더 연동을 해제할까요?', message: '체크 화면에 일정이 더 이상 보이지 않아요', confirmLabel: '해제');
              if (ok) app.disconnectCalendar();
            },
          ),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final int n;
  final String text;

  const _StepLine(this.n, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Palette.soft(Palette.accent), shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.accent)),
          ),
          const SizedBox(width: Space.m),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(text, style: Txt.body.copyWith(fontSize: 19)))),
        ],
      ),
    );
  }
}

class _ConnectedFlash extends StatelessWidget {
  const _ConnectedFlash();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(color: const Color(0xF21C2541), borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.card),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(color: Palette.soft(Palette.done), shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 58, color: Palette.done),
              ),
              const SizedBox(height: Space.l),
              const Text('연동됐어요', style: Txt.hero),
            ],
          ),
        ),
      ),
    );
  }
}
