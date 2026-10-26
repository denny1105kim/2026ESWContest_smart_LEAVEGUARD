import 'package:flutter/material.dart';

import '../../core/config/constants.dart';

/// 화면별 설계 크기로 그린 뒤 실제 화면에 맞춰 같은 비율로 늘리거나 줄인다.
class DesignCanvas extends StatelessWidget {
  final Size size;
  final Widget child;

  final double? fitWidth;

  const DesignCanvas({super.key, required this.size, required this.child}) : fitWidth = null;

  /// 1024×600 설계 화면.
  const DesignCanvas.legacy({super.key, required this.child})
      : size = const Size(screenW, screenH),
        fitWidth = null;

  /// 가로만 [width] 에 맞추고 세로는 화면 비율대로 늘린다 (자식은 세로가 늘어날 수 있어야 한다).
  const DesignCanvas.fitWidth({super.key, required this.child, double width = 1920})
      : size = Size.zero,
        fitWidth = width;

  @override
  Widget build(BuildContext context) {
    final width = fitWidth;
    if (width != null) {
      return LayoutBuilder(builder: (context, c) {
        final height = c.maxWidth > 0 && c.maxHeight.isFinite ? width * c.maxHeight / c.maxWidth : width * 9 / 16;
        return SizedBox.expand(
          child: FittedBox(fit: BoxFit.fill, child: SizedBox(width: width, height: height, child: child)),
        );
      });
    }
    // FittedBox 는 느슨한 제약에선 확대하지 않아 먼저 공간을 꽉 채운다
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.fromSize(size: size, child: child),
      ),
    );
  }
}
