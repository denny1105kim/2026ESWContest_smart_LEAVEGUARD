import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

enum ButtonTone { primary, ghost, danger, outline }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonTone tone;
  final bool loading;
  final bool expand;
  final double height;

  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.tone = ButtonTone.primary,
    this.loading = false,
    this.expand = false,
    this.height = kTouch,
  });

  const AppButton.ghost(this.label, {super.key, this.onPressed, this.icon, this.loading = false, this.expand = false, this.height = kTouch})
      : tone = ButtonTone.ghost;

  const AppButton.danger(this.label, {super.key, this.onPressed, this.icon, this.loading = false, this.expand = false, this.height = kTouch})
      : tone = ButtonTone.danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final (bg, fg, border) = switch (tone) {
      ButtonTone.primary => (Colors.white, Palette.ink, null),
      ButtonTone.ghost => (Palette.raised, Palette.text, null),
      ButtonTone.danger => (Palette.pending, Colors.white, null),
      ButtonTone.outline => (Colors.transparent, Palette.text, Palette.line),
    };
    final background = enabled || loading ? bg : const Color(0x14FFFFFF);
    final foreground = enabled || loading ? fg : Palette.faint;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: foreground))
        else if (icon != null)
          Icon(icon, size: 22, color: foreground),
        if (loading || icon != null) const SizedBox(width: Space.s),
        Text(label, style: Txt.button.copyWith(color: foreground)),
      ],
    );

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.button),
        boxShadow: enabled && tone == ButtonTone.danger ? Shadows.glow(bg) : null,
      ),
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          side: border == null ? BorderSide.none : BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: content),
        ),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Color background;
  final double size;

  const RoundIconButton(this.icon, {super.key, this.onPressed, this.color, this.background = Palette.surface, this.size = kTouch});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: background == Palette.surface ? Shadows.card : null),
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Icon(icon, size: size * 0.44, color: color ?? Palette.text),
        ),
      ),
    );
  }
}
