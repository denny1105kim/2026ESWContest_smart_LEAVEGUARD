import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/models.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/design_canvas.dart';

Future<bool> confirmSameItem(BuildContext context, Belonging b, Uint8List? crop) async {
  Widget photo(Uint8List? bytes, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.button),
            child: Container(
              height: 170,
              width: double.infinity,
              color: Palette.raised,
              child: bytes == null ? const Icon(Icons.image_not_supported_outlined, color: Palette.faint, size: 40) : Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(label, style: Txt.caption),
        ],
      );
  final result = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0xFF101322).withValues(alpha: 0.55),
    builder: (context) => DesignCanvas.legacy(
      child: Dialog(
        backgroundColor: Palette.dialog,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 560,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('‘${b.name}’ 맞나요?', style: Txt.title.copyWith(fontSize: 26)),
                const SizedBox(height: Space.xs),
                const Text('같은 이름의 물건이 있어요. 맞으면 이 모습을 그 물건에 더해서, 다음부터 이렇게 놓여도 알아봐요', style: Txt.caption),
                const SizedBox(height: Space.l),
                Row(
                  children: [
                    Expanded(child: photo(crop, '지금 고른 모습')),
                    const SizedBox(width: Space.m),
                    Expanded(child: photo(b.thumbnail, '‘${b.name}’ 등록한 사진')),
                  ],
                ),
                const SizedBox(height: Space.xl),
                Row(
                  children: [
                    Expanded(child: AppButton.ghost('아니에요', expand: true, onPressed: () => Navigator.pop(context, false))),
                    const SizedBox(width: Space.m),
                    Expanded(child: AppButton('맞아요', expand: true, onPressed: () => Navigator.pop(context, true))),
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
