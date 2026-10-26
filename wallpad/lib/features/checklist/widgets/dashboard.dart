part of '../checklist_screen.dart';

// 출근·귀가 화면 공통 틀과 부품. 1920 폭 기준 픽셀
abstract final class _D {
  static const pad = 64.0;
  static const top = 28.0;
  static const topRow = 60.0;
  static const heroWidth = 624.0;
  static const upperHeight = 413.0;
  static const gap = 24.0;

  // OS 가 화면 맨 아래 터치를 앱 닫기 스와이프로 받으므로 버튼을 그 위에 둔다
  static const bottom = 92.0;
  static const sideWidth = 420.0;
  static const radius = 32.0;

  static const panel = Color(0x14FFFFFF);
  static const line = Color(0x1FFFFFFF);
  static const faint = Color(0x8CFFFFFF);
  static const dim = Color(0x66FFFFFF);
  static const soft = Color(0xFF9DB4FF);
  static const red = Color(0xFFFF6B6B);
  static const orange = Color(0xFFFFA94D);
  static const green = Color(0xFF3CCB8A);

  // 남색 카드 위에서 읽히게 조금 밝힌다
  static Color nameColor(Color c) => Color.lerp(c, Colors.white, 0.3)!;

  static TextStyle t(double size, {FontWeight w = FontWeight.w400, Color c = Colors.white, double h = 1.25, double ls = 0}) => TextStyle(
        fontFamily: WallpadTokens.fontFamily,
        fontFamilyFallback: WallpadTokens.fontFallback,
        fontSize: size,
        fontWeight: w,
        color: c,
        height: h,
        letterSpacing: ls,
      );
}

/// 위 줄은 높이 고정, 남는 세로는 아래 줄이 받는다
class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.topRow, required this.hero, required this.upper, required this.lower, required this.side});

  final Widget topRow, hero, upper, lower, side;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_D.pad, _D.top, _D.pad, _D.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: _D.topRow, child: topRow),
          const SizedBox(height: 32),
          SizedBox(
            height: _D.upperHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [SizedBox(width: _D.heroWidth, child: hero), const SizedBox(width: 32), Expanded(child: upper)],
            ),
          ),
          const SizedBox(height: _D.gap),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(child: lower), const SizedBox(width: _D.gap), SizedBox(width: _D.sideWidth, child: side)],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(32)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: WallpadTokens.surface, borderRadius: BorderRadius.circular(_D.radius)),
      child: child,
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.title, {this.trailing, this.trailingColor = _D.faint});

  final String title;
  final String? trailing;
  final Color trailingColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Text(title, style: _D.t(23, w: FontWeight.w600)),
          const Spacer(),
          if (trailing != null) Text(trailing!, style: _D.t(16, c: trailingColor, w: trailingColor == _D.faint ? FontWeight.w400 : FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color, this.background, this.onTap});

  final String text;
  final Color color;
  final Color? background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background ?? color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
      child: Text(text, style: _D.t(15, w: FontWeight.w600, c: color, h: 1)),
    );
    if (onTap == null) return pill;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(10), child: pill),
    );
  }
}

class _WhiteButton extends StatelessWidget {
  const _WhiteButton({required this.label, required this.onPressed, this.icon, this.height = 68});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Material(
        color: onPressed == null ? const Color(0x33FFFFFF) : Colors.white,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 26, color: WallpadTokens.ink), const SizedBox(width: 10)],
              Text(label, style: _D.t(23, w: FontWeight.w600, c: WallpadTokens.ink, h: 1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftButton extends StatelessWidget {
  const _SoftButton({required this.label, required this.onPressed, this.color});

  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Material(
        color: color ?? const Color(0x24FFFFFF),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onPressed, child: Center(child: Text(label, style: _D.t(20, w: FontWeight.w600, h: 1)))),
      ),
    );
  }
}
