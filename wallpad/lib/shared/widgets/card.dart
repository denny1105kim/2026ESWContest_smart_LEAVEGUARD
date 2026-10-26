import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;
  final Widget child;
  final Color? accent;
  final bool fill; // 내용이 남은 높이를 다 쓴다

  const SectionCard({super.key, required this.title, required this.icon, required this.child, this.trailing, this.accent, this.fill = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.l, 10, Space.l, 10),
      decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: Palette.soft(accent ?? Palette.accent), shape: BoxShape.circle),
                  child: Icon(icon, size: 17, color: accent ?? Palette.accent),
                ),
                const SizedBox(width: 10),
                Text(title, style: Txt.section),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (fill) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class EmptyNote extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const EmptyNote({super.key, required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(Radii.button)),
            child: Icon(icon, color: Palette.faint, size: 22),
          ),
          const SizedBox(width: Space.m),
          Expanded(child: Text(text, style: Txt.sub)),
          if (action != null) action!,
        ],
      ),
    );
  }
}
