import 'package:flutter/material.dart';

import '../../shared/widgets/logo.dart';

/// 온보딩 화면 색과 공통 부품 (1920x1080 기준)
abstract final class Ob {
  static const navy = Color(0x8C1C2541);
  static const navyCard = Color(0x1FFFFFFF);
  static const navyLine = Color(0x29FFFFFF);
  static const navyStep = Color(0x29FFFFFF);
  static const navyConnector = Color(0x33FFFFFF);
  static const bg = Colors.transparent; // 바탕 그라데이션이 비쳐야 한다
  static const card = Color(0xDE1C2541);
  static const dialog = Color(0xFF232B4A);
  static const ink = Color(0xFF1C2541);
  static const accent = Color(0xFF6F89FF);
  static const accentTint = Color(0x474C6FFF);
  static const line = Color(0x29FFFFFF);
  static const text = Color(0xFFFFFFFF);
  static const muted = Color(0xB8FFFFFF);
  static const faint = Color(0x80FFFFFF);
  static const green = Color(0xFF22A06B);
  static const greenTint = Color(0x3822A06B);
  static const red = Color(0xFFE5484D);
  static const redTint = Color(0x38E5484D);
  static const chip = Color(0x17FFFFFF);

  static const title = TextStyle(fontSize: 46, fontWeight: FontWeight.w300, color: text, height: 1.25, letterSpacing: -0.8);
  static const cardTitle = TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: text, height: 1.3);
  static const label = TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: text, height: 1.3);
  static const small = TextStyle(fontSize: 19, fontWeight: FontWeight.w500, color: muted, height: 1.3);

  static const steps = ['이름', '얼굴', '생활 패턴', '소지품', '챙길 것', '캘린더'];
}

class ObSidebar extends StatelessWidget {
  final int memberNo;
  final String name;
  final int step; // 6 이면 모두 끝
  final Color avatarColor;

  const ObSidebar({super.key, required this.memberNo, required this.name, required this.step, required this.avatarColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 430,
      color: Ob.navy,
      padding: const EdgeInsets.fromLTRB(50, 36, 50, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              LogoMark(height: 38, onDark: true),
              SizedBox(width: 22),
              Text('LeaveGuard', style: TextStyle(fontSize: 31, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 62),
          Text('MEMBER ${memberNo.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Ob.faint, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(name.isEmpty ? '새 멤버 설정' : '$name님의 설정',
              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 18),
          Container(height: 1, color: Ob.navyLine),
          const SizedBox(height: 47),
          for (var i = 0; i < Ob.steps.length; i++) ...[
            if (i > 0) Padding(padding: const EdgeInsets.only(left: 18), child: Container(width: 2, height: 45, color: i <= step ? Ob.green : Ob.navyConnector)),
            _StepRow(index: i, label: Ob.steps[i], state: i < step ? _Step.done : (i == step ? _Step.now : _Step.todo)),
          ],
          const Spacer(),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 56),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: BoxDecoration(color: Ob.navyCard, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: avatarColor, shape: BoxShape.circle),
                      child: Text(name.isEmpty ? '?' : name.characters.first, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(name.isEmpty ? '새 멤버' : name,
                          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('나만의 외출 준비 설정 중', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w500, color: Ob.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Step { done, now, todo }

class _StepRow extends StatelessWidget {
  final int index;
  final String label;
  final _Step state;

  const _StepRow({required this.index, required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (state) {
      _Step.done => (Ob.green, Colors.white),
      _Step.now => (Colors.white, Ob.ink),
      _Step.todo => (Ob.navyStep, Ob.faint),
    };
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: state == _Step.done
              ? const Icon(Icons.check_rounded, size: 24, color: Colors.white)
              : Text('${index + 1}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: fg)),
        ),
        const SizedBox(width: 19),
        Text(label,
            style: TextStyle(
              fontSize: 25,
              fontWeight: state == _Step.now ? FontWeight.w700 : FontWeight.w500,
              color: switch (state) { _Step.now => Colors.white, _Step.done => Ob.muted, _Step.todo => Ob.faint },
            )),
      ],
    );
  }
}

class ObHeader extends StatelessWidget {
  final String label;
  final double progress;
  final VoidCallback? onSkip;

  const ObHeader({super.key, required this.label, required this.progress, this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 72,
          child: Row(
            children: [
              const Spacer(),
              if (onSkip != null) _Link('건너뛰기', onTap: onSkip!),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Ob.muted)),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) => Stack(
            children: [
              Container(height: 6, decoration: BoxDecoration(color: Ob.navyConnector, borderRadius: BorderRadius.circular(3))),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                height: 6,
                width: c.maxWidth * progress.clamp(0, 1),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _Link(this.text, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Ob.muted)),
      ),
    );
  }
}

class ObButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final double width;

  const ObButton(this.label, {super.key, this.onTap, this.primary = true, this.width = 215});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final bg = primary ? (enabled ? Colors.white : Ob.chip) : Ob.navyCard;
    final fg = primary ? (enabled ? Ob.ink : Ob.faint) : Ob.text;
    return SizedBox(
      width: width,
      height: 80,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Container(
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: fg)),
          ),
        ),
      ),
    );
  }
}

class ObOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  const ObOptionCard({super.key, required this.icon, required this.title, required this.selected, required this.onTap, this.height = 199});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Material(
        color: selected ? Ob.accentTint : Ob.card,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(19, 19, 19, 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: selected ? Ob.accent : Colors.transparent, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(color: selected ? Ob.accent : Ob.chip, borderRadius: BorderRadius.circular(16)),
                      child: Icon(icon, size: 36, color: selected ? Colors.white : Ob.muted),
                    ),
                    const Spacer(),
                    if (selected) const ObCheck(),
                  ],
                ),
                const Spacer(),
                Text(title, style: Ob.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ObCheck extends StatelessWidget {
  final double size;
  final Color color;

  const ObCheck({super.key, this.size = 31, this.color = Ob.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(Icons.check_rounded, size: size * 0.66, color: Colors.white),
    );
  }
}

class ObPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;

  const ObPanel({super.key, required this.child, this.padding = const EdgeInsets.all(28), this.color = Ob.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }
}

class ObChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  const ObChip(this.label, {super.key, required this.selected, required this.onTap, this.height = 60});

  @override
  Widget build(BuildContext context) {
    final border = selected ? Ob.accent : Colors.transparent;
    return Material(
      color: selected ? Ob.accentTint : Ob.chip,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 2)),
          child: Text(label, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Ob.text)),
        ),
      ),
    );
  }
}
