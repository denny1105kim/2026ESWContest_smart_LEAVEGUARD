import 'package:flutter/material.dart';

import '../../features/auth/pin.dart';
import '../../core/theme/tokens.dart';

/// PIN 키패드. 입력 상태는 쓰는 쪽이 들고 있다.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.filled,
    required this.onDigit,
    required this.onBack,
    this.onCancel,
    this.message,
    this.error = false,
    this.locked = false,
    this.keyHeight = 58,
    this.keyColor = Palette.raised,
    this.keyBorder,
  });

  final int filled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBack;

  final VoidCallback? onCancel; // null 이면 [취소] 칸을 비운다
  final String? message;
  final bool error;
  final bool locked;
  final double keyHeight;
  final Color keyColor;
  final Color? keyBorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < Pin.length; i++)
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < filled ? Palette.accent : null,
                  border: Border.all(color: i < filled ? Palette.accent : Palette.faint, width: 2),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.s),
        SizedBox(
          height: 24,
          child: message == null ? null : Text(message!, style: Txt.caption.copyWith(fontSize: 16, color: error ? Palette.pending : Palette.muted)),
        ),
        const SizedBox(height: Space.s),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['취소', '0', '⌫'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Row(
              children: [
                for (final k in row) ...[
                  if (k != row.first) const SizedBox(width: Space.s),
                  Expanded(child: _key(k)),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _key(String k) {
    if (k == '취소' && onCancel == null) return SizedBox(height: keyHeight);
    final digit = RegExp(r'^\d$').hasMatch(k);
    final onTap = switch (k) {
      '취소' => onCancel,
      '⌫' => onBack,
      _ => locked ? null : () => onDigit(k),
    };
    final border = digit ? keyBorder : null;
    return Material(
      color: digit ? keyColor : Colors.transparent,
      elevation: 0,
      shadowColor: const Color(0x331C2541),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.button),
        side: border == null ? BorderSide.none : BorderSide(color: border, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: onTap,
        child: SizedBox(
          height: keyHeight,
          child: Center(
            child: k == '⌫'
                ? const Icon(Icons.backspace_outlined, size: 26, color: Palette.text)
                : Text(k,
                    style: digit ? Txt.title.copyWith(fontSize: 26, color: locked ? Palette.faint : Palette.text) : Txt.bodyStrong.copyWith(color: Palette.muted)),
          ),
        ),
      ),
    );
  }
}
