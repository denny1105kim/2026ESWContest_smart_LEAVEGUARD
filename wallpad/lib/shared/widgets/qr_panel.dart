import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../../core/theme/tokens.dart';

class QrPanel extends StatelessWidget {
  final String data;
  final double size;
  final bool expired;

  const QrPanel({super.key, required this.data, this.size = 240, this.expired = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.07),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.lifted),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: expired ? 0.12 : 1,
            child: CustomPaint(painter: _QrPainter(data)),
          ),
          if (expired)
            const Center(child: Icon(Icons.timer_off_rounded, size: 56, color: Color(0xFF111827))),
        ],
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final String data;
  final QrImage _image;

  _QrPainter(this.data) : _image = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));

  @override
  void paint(Canvas canvas, Size size) {
    final n = _image.moduleCount;
    final cell = size.width / n;
    final ink = Paint()..color = const Color(0xFF111827);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (_image.isDark(y, x)) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell).inflate(0.2), ink);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
