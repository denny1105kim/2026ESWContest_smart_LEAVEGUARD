import 'package:flutter/material.dart';

export 'wallpad_tokens.dart';

/// 1024×600 화면용 색. 상태는 색만으로 구분하지 않는다 (아이콘 + 글자)
class Palette {
  static const bg = Color(0xFF9996BE);
  static const bgTop = Color(0xFFCCA894);
  static const bgMid = Color(0xFFA89BB2);
  static const bgBottom = Color(0xFF6678D6);
  static const surface = Color(0xDE1C2541);
  static const dialog = Color(0xFF232B4A); // 장막 위에 뜨는 불투명 창
  static const glass = Color(0x731C2541);
  static const raised = Color(0x17FFFFFF); // 카드 안의 칸 · 버튼
  static const line = Color(0x24FFFFFF);
  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0xB8FFFFFF);
  static const faint = Color(0x80FFFFFF);
  static const ink = Color(0xFF1C2541); // 흰 버튼 위 글씨

  static const pending = Color(0xFFF0525A); // 안 챙김
  static const done = Color(0xFF22A06B); // 챙김
  static const warn = Color(0xFFF59A23); // 켜진 가전
  static const accent = Color(0xFF6F89FF);

  static const tray = Color(0xFF4C6FFF);
  static const today = Color(0xFF8B5CF6);

  static Color soft(Color c) => c.withValues(alpha: 0.22);
}

class Shadows {
  static const card = [BoxShadow(color: Color(0x141C2541), blurRadius: 24, offset: Offset(0, 6))];
  static const lifted = [BoxShadow(color: Color(0x401C2541), blurRadius: 40, offset: Offset(0, 14))];

  static List<BoxShadow> glow(Color c) => [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))];
}

class Radii {
  static const card = 24.0;
  static const button = 16.0;
  static const pill = 999.0;
}

class Space {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0;
}

class Txt {
  static const hero = TextStyle(fontSize: 40, fontWeight: FontWeight.w300, color: Palette.text, height: 1.2, letterSpacing: -1);
  static const title = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Palette.text, height: 1.25, letterSpacing: -0.6);
  static const body = TextStyle(fontSize: 20, color: Palette.text, height: 1.3);
  static const bodyStrong = TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Palette.text, height: 1.3);
  static const sub = TextStyle(fontSize: 17, color: Palette.muted, height: 1.35);
  static const section = TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.text, letterSpacing: -0.3);
  static const caption = TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Palette.faint);
  static const button = TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.2);
}

const kTouch = 56.0;

// 6비트 패널이지만 Flutter 가 그라데이션을 디더링해 밴딩이 거의 안 보인다
class WallpadBackground extends StatelessWidget {
  final Widget child;
  final bool night; // 귀가 화면의 저녁 바탕

  const WallpadBackground({super.key, required this.child, this.night = false});

  static const gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Palette.bgTop, Palette.bgMid, Palette.bgBottom],
    stops: [0, 0.4, 1],
  );

  static const evening = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF3C4A8C), Color(0xFF7A6DAD), Color(0xFFC09095), Color(0xFFE3A07E)],
    stops: [0, 0.4, 0.8, 1],
  );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: DecoratedBox(decoration: BoxDecoration(gradient: night ? evening : gradient), child: child));
  }
}
