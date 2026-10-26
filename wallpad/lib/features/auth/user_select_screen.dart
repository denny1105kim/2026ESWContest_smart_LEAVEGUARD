import 'package:flutter/material.dart';

import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/buttons.dart';
import '../../app/app_state.dart';
import '../../app/models.dart';
import '../../core/theme/tokens.dart';

class UserSelectScreen extends StatelessWidget {
  const UserSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    watch(context);
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 36, 40, 40),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('누구세요?', style: Txt.hero),
                    ],
                  ),
                ),
                AppButton.ghost('다시 인식', icon: Icons.face_rounded, onPressed: () => app.go(Stage.identifying)),
              ],
            ),
            Expanded(
              child: Center(
                child: Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final u in app.listedUsers) _UserTile(u),
                    const _AddTile(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool outlined;

  const _Tile({required this.child, required this.onTap, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 184,
      height: 208,
      child: Material(
        color: outlined ? Palette.glass : Palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: outlined ? const BorderSide(color: Palette.line, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: child),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final User user;

  const _UserTile(this.user);

  @override
  Widget build(BuildContext context) {
    watch(context);
    return _Tile(
      onTap: () => app.selectUser(user.id),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Avatar(user, size: 100),
          const SizedBox(height: Space.l),
          Text(user.name, style: Txt.title.copyWith(fontSize: 24)),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile();

  @override
  Widget build(BuildContext context) {
    return _Tile(
      outlined: true,
      onTap: () => app.startOnboarding(Stage.userSelect),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(color: Palette.soft(Palette.accent), shape: BoxShape.circle),
            child: const Icon(Icons.add_rounded, size: 44, color: Palette.accent),
          ),
          const SizedBox(height: Space.l),
          Text('새 사용자', style: Txt.title.copyWith(fontSize: 24, color: Palette.muted)),
        ],
      ),
    );
  }
}
