import 'package:flutter/material.dart';

/// LeaveGuard 로고 (열린 문, 100×120 기준 도형).
class LogoMark extends StatelessWidget {
  final double height;
  final bool onDark;

  const LogoMark({super.key, this.height = 40, this.onDark = false});

  static const navy = Color(0xFF16192C);
  static const green = Color(0xFF22A06B);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: height * 100 / 120,
      height: height,
      child: CustomPaint(painter: _DoorPainter(door: onDark ? Colors.white : navy, knob: onDark ? navy : Colors.white)),
    );
  }
}

class _DoorPainter extends CustomPainter {
  final Color door, knob;

  const _DoorPainter({required this.door, required this.knob});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 120);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(6, 10, 58, 102), const Radius.circular(7)), Paint()..color = door);
    canvas.drawCircle(const Offset(50, 64), 5.5, Paint()..color = knob);
    final leaf = Path()
      ..moveTo(64, 10)
      ..lineTo(94, 1)
      ..lineTo(94, 119)
      ..lineTo(81, 119)
      ..lineTo(81, 15)
      ..lineTo(64, 19)
      ..close();
    canvas.drawPath(leaf, Paint()..color = LogoMark.green);
  }

  @override
  bool shouldRepaint(_DoorPainter old) => old.door != door || old.knob != knob;
}
