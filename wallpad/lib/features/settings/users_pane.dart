import 'package:flutter/material.dart';

import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/tags.dart';
import '../../app/app_state.dart';
import '../../app/models.dart';
import '../../core/theme/tokens.dart';
import 'settings_screen.dart';

class UsersPane extends StatelessWidget {
  const UsersPane({super.key});

  @override
  Widget build(BuildContext context) {
    watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(
          title: '사용자 관리',
          action: AppButton('사용자 등록', icon: Icons.person_add_alt_1_rounded, onPressed: () => app.startOnboarding(Stage.settings)),
        ),
        const SizedBox(height: Space.xl),
        Expanded(
          child: ListView.separated(
            itemCount: app.listedUsers.length,
            separatorBuilder: (_, __) => const SizedBox(height: Space.m),
            itemBuilder: (context, i) => _UserRow(app.listedUsers[i]),
          ),
        ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  final User user;

  const _UserRow(this.user);

  @override
  Widget build(BuildContext context) {
    watch(context);
    final belongings = app.belongingsOf(user.id).length;
    final current = user.id == app.userId;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.m, Space.m),
      decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.card),
      child: Row(
        children: [
          Avatar(user, size: 56),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(user.name, style: Txt.bodyStrong),
                    if (current) ...[const SizedBox(width: Space.s), const StatusTag('지금 사용 중', color: Palette.accent)],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '소지품 $belongings · ${!user.calendarLinked ? '캘린더 미연동' : user.calendarNeedsReauth ? '캘린더 다시 연동 필요' : '캘린더 연동됨'}',
                  style: Txt.caption,
                ),
              ],
            ),
          ),
          RoundIconButton(
            Icons.delete_outline_rounded,
            color: Palette.pending,
            background: Palette.soft(Palette.pending),
            onPressed: () async {
              final ok = await confirmDelete(
                context,
                title: '${user.name}님을 삭제할까요?',
                message: '소지품·캘린더 연동이 모두 삭제돼요',
              );
              if (ok) app.requestDeleteUser(user); // 본인 확인 뒤에 지운다
            },
          ),
        ],
      ),
    );
  }
}
