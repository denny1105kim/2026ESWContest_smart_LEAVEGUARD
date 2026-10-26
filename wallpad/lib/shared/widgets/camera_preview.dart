import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

class CameraPreviewBox extends StatelessWidget {
  final double width, height;
  final bool circle;
  final IconData icon;
  final String? label;
  final Widget? overlay;
  final ui.Image? frame;

  const CameraPreviewBox({
    super.key,
    required this.width,
    required this.height,
    this.circle = false,
    this.icon = Icons.person_rounded,
    this.label,
    this.overlay,
    this.frame,
  });

  /// BoxFit.cover 로 잘린 뒤 [box] 에 보이는 영상 영역 (0~1).
  static Rect visibleArea(Size box, {double frameWidth = 320, double frameHeight = 240}) {
    final scale = max(box.width / frameWidth, box.height / frameHeight);
    final w = box.width / (frameWidth * scale), h = box.height / (frameHeight * scale);
    return Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 0.9,
              colors: [Color(0xFF2A3354), Color(0xFF1C2541)],
            ),
          ),
        ),
        if (frame == null)
          Center(child: Icon(icon, size: height * 0.42, color: Colors.white.withValues(alpha: 0.35)))
        else
          RawImage(image: frame, fit: BoxFit.cover),
        if (overlay != null) overlay!,
        if (label != null)
          Positioned(
            left: Space.m,
            top: Space.m,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(Radii.pill)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Palette.pending, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(label!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
    );
    return SizedBox(
      width: width,
      height: height,
      child: circle ? ClipOval(child: body) : ClipRRect(borderRadius: BorderRadius.circular(Radii.card), child: body),
    );
  }
}
