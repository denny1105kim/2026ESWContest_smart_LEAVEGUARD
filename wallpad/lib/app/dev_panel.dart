import 'package:flutter/material.dart';

import '../core/config/app_clock.dart';
import '../features/belongings/tray_status.dart';
import 'backend.dart' show onBoard;
import 'app_state.dart';
import '../core/theme/tokens.dart';
import '../shared/time_text.dart';

class DevPanel extends StatefulWidget {
  const DevPanel({super.key});

  @override
  State<DevPanel> createState() => _DevPanelState();
}

class _DevPanelState extends State<DevPanel> {
  var _open = false;

  static const _stageNames = {
    Stage.idle: 'IDLE',
    Stage.identifying: 'IDENTIFYING',
    Stage.userSelect: 'USER_SELECT',
    Stage.checklist: 'CHECKLIST',
    Stage.returning: 'RETURN',
    Stage.settings: 'SETTINGS',
    Stage.welcome: 'WELCOME',
    Stage.onboarding: 'ONBOARDING',
  };

  @override
  Widget build(BuildContext context) {
    watch(context);
    final handle = GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text('DEV · ${_stageNames[app.stage]}${AppClock.shifted ? ' · ${AppClock.now().month}/${AppClock.now().day} ${hhmm(AppClock.now())}' : ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB4BCC8), letterSpacing: 0.5)),
      ),
    );

    return Positioned(
      top: 4,
      left: 0,
      right: 0,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            handle,
            if (_open) ...[const SizedBox(height: 6), _panel()],
          ],
        ),
      ),
    );
  }

  Widget _panel() {
    final user = app.user;
    final tray = user == null ? app.belongings : app.myBelongings;
    return Container(
      width: 680,
      constraints: const BoxConstraints(maxHeight: 520),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xF0202430),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(child: _demo('출근 07:30', Icons.wb_sunny_rounded, const Color(0xFF4C6FFF), app.demoMorning)),
                  const SizedBox(width: 8),
                  Expanded(child: _demo('복귀 18:00', Icons.nightlight_round, const Color(0xFFE88A24), app.demoEvening)),
                  const SizedBox(width: 8),
                  Expanded(child: _demo('내일 출근', Icons.event_repeat_rounded, const Color(0xFF7B5CFF), app.demoNextMorning)),
                  const SizedBox(width: 8),
                  Expanded(child: _demo('전체 초기화', Icons.restart_alt_rounded, const Color(0xFF5A6070), app.demoResetAll)),
                  const SizedBox(width: 8),
                  Expanded(child: _demo('사용자 초기화', Icons.person_remove_rounded, const Color(0xFFC0392B), () => app.demoResetUsers().ignore())),
                ],
              ),
            ),
            _group('흐름', [
              _btn('모션 감지', app.motion),
              for (final u in app.users) _btn('얼굴 성공 · ${u.name}', () => app.faceSucceeded(u.id)),
              _btn('얼굴 실패', app.faceFailed),
              _btn('외출 판정', app.leaving),
              _btn('귀가 판정', app.returning),
              _btn('현관 무인', app.entranceEmpty),
              _btn('본인 확인 통과', app.devPassAuth),
            ]),
            _group('트레이 (누를 때마다: 있음 → 챙김 → 어제부터 없음 → 다른 주인이 가져감)', [
              for (final b in tray) _toggle('${b.name} · ${_trayLabel(app.statusOf(b.id, app.userId))}', app.statusOf(b.id, app.userId) == TrayStatus.onTray, () => app.cycleTray(b.id)),
              _toggle('카메라 끊김', app.trayOffline, () => app.setTrayOffline(!app.trayOffline)),
            ]),
            _group('오늘 챙길 것 (날씨)', [
              _toggle('미세먼지 나쁨 (마스크)', app.devAirBad, () => app.setDevAirBad(!app.devAirBad)),
              _toggle('자외선 6 (선크림)', app.devUvHigh, () => app.setDevUvHigh(!app.devUvHigh)),
              _toggle('일교차 14° (겉옷)', app.devBigGap, () => app.setDevBigGap(!app.devBigGap)),
            ]),
            _group('귀가 (내일 챙길 것)', [
              _toggle('내일 비 70% · 일교차 11°', app.devTomorrowRain, () => app.setDevTomorrowRain(!app.devTomorrowRain)),
            ]),
            _group('공통 일정', [
              for (final t in app.familyTodos) _toggle(t.name, t.done, () => app.toggleFamilyTodo(t.id)),
            ]),
            _group(onBoard ? '가전 (누르면 플러그 다시 켜기)' : '가전 전류', [
              for (final a in app.appliances) _toggle(a.name, a.isOn, () => app.toggleAppliance(a.id)),
              _toggle('다음 끄기 실패', app.failNextTurnOff, () => app.setFailNextTurnOff(!app.failNextTurnOff)),
            ]),
            _group('현관 카메라 (ESP32 없이 흉내)', [
              _btn('얼굴 1초 누적 → 확인 중', app.devDoorDetected),
              for (final u in app.users) _btn('아는 사람 · ${u.name}', () => app.devDoorKnown(u.id)),
              _btn('모르는 사람', app.devDoorUnknown),
              _btn('사람 사라짐', app.devDoorGone),
              _toggle('카메라 끊김', !app.doorOnline, () => app.setDoorOnline(!app.doorOnline)),
            ]),
            _group('캘린더', [
              _btn('폰에서 연동 완료', app.calendarSaved),
              _toggle('불러오기 실패', app.calendarFailed, () => app.setCalendarFailed(!app.calendarFailed)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _group(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.faint, letterSpacing: 0.4)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: children),
        ],
      ),
    );
  }

  static String _trayLabel(TrayStatus s) => switch (s) {
        TrayStatus.onTray => '있음',
        TrayStatus.notReturned => '어제부터 없음',
        TrayStatus.takenByOther => '다른 주인이 가져감',
        TrayStatus.acknowledged => '알고 있음',
        TrayStatus.unknown => '미확인',
        TrayStatus.taken => '챙김',
      };

  Widget _btn(String label, VoidCallback onTap) => _chip(label, false, onTap, button: true);

  Widget _demo(String label, IconData icon, Color color, VoidCallback onTap) => Material(
        color: color,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            onTap();
            setState(() => _open = false);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            ),
          ),
        ),
      );

  Widget _toggle(String label, bool on, VoidCallback onTap) => _chip(label, on, onTap);

  Widget _chip(String label, bool on, VoidCallback onTap, {bool button = false}) {
    return Material(
      color: on ? Palette.accent : Palette.raised,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!button) ...[
                Icon(on ? Icons.toggle_on_rounded : Icons.toggle_off_rounded, size: 18, color: on ? Colors.white : Palette.faint),
                const SizedBox(width: 4),
              ],
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? Colors.white : Palette.text)),
            ],
          ),
        ),
      ),
    );
  }
}
