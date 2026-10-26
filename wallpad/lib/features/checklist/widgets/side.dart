part of '../checklist_screen.dart';

class _Percent extends StatelessWidget {
  const _Percent(this.value);

  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$value', style: _D.t(120, w: FontWeight.w200, h: 1, ls: -2)),
        const SizedBox(width: 10),
        Text('%', style: _D.t(36, w: FontWeight.w300, c: _D.faint)),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.value);

  final double value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          Container(height: 5, decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(3))),
          AnimatedContainer(
            duration: WallpadTokens.completionTransition,
            curve: Curves.easeOutCubic,
            height: 5,
            width: c.maxWidth * value.clamp(0.0, 1.0),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
          ),
        ],
      ),
    );
  }
}

class _SideNotice extends StatelessWidget {
  const _SideNotice({required this.title, required this.icon, required this.color, required this.headline, required this.detail, this.big, this.buttons = const []});

  final String title;
  final IconData icon;
  final Color color;
  final String headline;
  final String detail;

  /// 있으면 아이콘 대신 크게 보인다
  final String? big;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head(title),
          const Spacer(),
          if (big != null && big!.isNotEmpty)
            Text(big!, style: _D.t(104, w: FontWeight.w200, h: 1, ls: -2))
          else
            Align(alignment: Alignment.centerLeft, child: Icon(icon, size: 52, color: color)),
          const SizedBox(height: 14),
          Text(headline, style: _D.t(28, w: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(detail, style: _D.t(17, c: color == _D.soft ? _D.faint : color), maxLines: 3, overflow: TextOverflow.ellipsis),
          const Spacer(flex: 2),
          for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(height: 12), buttons[i]],
        ],
      ),
    );
  }
}
