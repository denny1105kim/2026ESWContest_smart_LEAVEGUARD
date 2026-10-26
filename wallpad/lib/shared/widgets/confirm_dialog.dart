import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'buttons.dart';
import 'design_canvas.dart';

Future<bool> confirmDelete(BuildContext context,
    {required String title, String? message, String confirmLabel = '삭제', IconData icon = Icons.delete_outline_rounded}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0xFF101322).withValues(alpha: 0.55),
    builder: (context) => DesignCanvas.legacy(
      child: Dialog(
        backgroundColor: Palette.dialog,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 440,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Palette.soft(Palette.pending), shape: BoxShape.circle),
                  child: Icon(icon, color: Palette.pending, size: 26),
                ),
                const SizedBox(height: Space.l),
                Text(title, style: Txt.title.copyWith(fontSize: 24)),
                if (message != null) ...[
                  const SizedBox(height: Space.s),
                  Text(message, style: Txt.sub),
                ],
                const SizedBox(height: Space.xl),
                Row(
                  children: [
                    Expanded(child: AppButton.ghost('취소', expand: true, onPressed: () => Navigator.pop(context, false))),
                    const SizedBox(width: Space.m),
                    Expanded(child: AppButton.danger(confirmLabel, expand: true, onPressed: () => Navigator.pop(context, true))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}
