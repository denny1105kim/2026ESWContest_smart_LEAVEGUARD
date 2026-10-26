import 'package:flutter/material.dart';

import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/buttons.dart';
import '../../app/app_state.dart';
import '../../core/theme/tokens.dart';
import 'appliance_pane.dart';
import 'belongings_pane.dart';
import 'calendar_pane.dart';
import 'clock_pane.dart';
import 'profile_pane.dart';
import 'users_pane.dart';
import 'wifi/wifi_pane.dart';

/// 왼쪽 메뉴, 오른쪽 상세. 지금 로그인한 사용자 기준
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _menu = [
    (SettingsPane.belongings, Icons.inventory_2_rounded, '소지품 등록'),
    (SettingsPane.calendar, Icons.calendar_month_rounded, '캘린더 연동'),
    (SettingsPane.users, Icons.group_rounded, '사용자 관리'),
    (SettingsPane.wifi, Icons.wifi_rounded, 'Wi-Fi'),
    (SettingsPane.appliances, Icons.local_laundry_service_rounded, '가전 연결'),
    (SettingsPane.clock, Icons.schedule_rounded, '화면 시각'),
  ];

  @override
  Widget build(BuildContext context) {
    watch(context);
    final user = app.user;
    return Material(
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 280,
            margin: const EdgeInsets.fromLTRB(Space.l, Space.l, 0, Space.l),
            decoration: BoxDecoration(color: Palette.glass, borderRadius: BorderRadius.circular(Radii.card)),
            padding: const EdgeInsets.all(Space.xl - 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton.ghost('돌아가기', icon: Icons.arrow_back_rounded, onPressed: () => app.go(Stage.checklist)),
                ),
                const SizedBox(height: Space.xl),
                if (user != null)
                  _MenuBox(
                    selected: app.settingsPane == SettingsPane.profile,
                    onTap: () => app.showPane(SettingsPane.profile),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.s),
                      child: Row(
                        children: [
                          Avatar(user, size: 48),
                          const SizedBox(width: Space.m),
                          Expanded(child: Text('${user.name}님의 설정', style: Txt.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Icon(Icons.chevron_right_rounded, color: app.settingsPane == SettingsPane.profile ? Palette.text : Palette.faint),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: Space.xl),
                for (final (pane, icon, label) in _menu)
                  _MenuItem(icon: icon, label: label, selected: app.settingsPane == pane, onTap: () => app.showPane(pane)),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.only(left: Space.xs),
                  child: Text('LeaveGuard 1.0.0', style: Txt.caption),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, Space.xl + 4, Space.xxl, Space.xl),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: switch (app.settingsPane) {
                  SettingsPane.belongings => const BelongingsPane(key: ValueKey('b')),
                  SettingsPane.calendar => const CalendarPane(key: ValueKey('c')),
                  SettingsPane.users => const UsersPane(key: ValueKey('u')),
                  SettingsPane.wifi => const WifiPane(key: ValueKey('wifi')),
                  SettingsPane.appliances => const AppliancePane(key: ValueKey('thinq')),
                  SettingsPane.clock => const ClockPane(key: ValueKey('clock')),
                  SettingsPane.profile => const ProfilePane(key: ValueKey('p')),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MenuItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _MenuBox(
      selected: selected,
      onTap: onTap,
      child: SizedBox(
        height: kTouch,
        child: Row(
          children: [
            const SizedBox(width: Space.m),
            Icon(icon, size: 24, color: selected ? Palette.text : Palette.muted),
            const SizedBox(width: Space.m),
            Expanded(child: Text(label, style: selected ? Txt.bodyStrong : Txt.body.copyWith(color: Palette.muted))),
            if (selected) const Icon(Icons.chevron_right_rounded, color: Palette.text),
            const SizedBox(width: Space.s),
          ],
        ),
      ),
    );
  }
}

class _MenuBox extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _MenuBox({required this.selected, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Space.xs),
      child: Material(
        color: selected ? const Color(0x1FFFFFFF) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          side: selected ? const BorderSide(color: Color(0x66FFFFFF)) : BorderSide.none,
        ),
        child: InkWell(borderRadius: BorderRadius.circular(Radii.button), onTap: onTap, child: child),
      ),
    );
  }
}

/// 상세 영역 머리글
class PaneHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final VoidCallback? onBack;

  const PaneHeader({super.key, required this.title, this.subtitle, this.action, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null) ...[
          RoundIconButton(Icons.arrow_back_rounded, onPressed: onBack),
          const SizedBox(width: Space.l),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Txt.title.copyWith(fontWeight: FontWeight.w300)),
              if (subtitle case final s?) ...[
                const SizedBox(height: 2),
                Text(s, style: Txt.sub, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

/// 누르면 화면 키보드가 열리는 입력칸
class FieldBox extends StatelessWidget {
  final String value;
  final String hint;
  final VoidCallback onTap;

  const FieldBox({super.key, required this.value, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Material(
        color: Palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l + 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value.isEmpty ? hint : value,
                    style: TextStyle(fontSize: 22, fontWeight: value.isEmpty ? FontWeight.w400 : FontWeight.w600, color: value.isEmpty ? Palette.faint : Palette.text),
                  ),
                ),
                const Icon(Icons.keyboard_rounded, color: Palette.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
