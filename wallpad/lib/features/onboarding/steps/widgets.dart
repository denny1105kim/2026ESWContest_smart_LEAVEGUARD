part of '../onboarding_screen.dart';

/// 좌우로 밀거나 양옆 값을 눌러 10분씩 바꾸는 시각 선택
class _TimeStepper extends StatefulWidget {
  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  const _TimeStepper({required this.label, required this.minutes, required this.onChanged});

  @override
  State<_TimeStepper> createState() => _TimeStepperState();
}

class _TimeStepperState extends State<_TimeStepper> with SingleTickerProviderStateMixin {
  // 밀 수 있다는 힌트로 화살표를 세 번 흔든다
  late final AnimationController _nudge;

  @override
  void initState() {
    super.initState();
    _nudge = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _nudge.repeat(count: 3);
    });
  }

  @override
  void dispose() {
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = widget.minutes;
    Widget side(int delta) => Expanded(
          child: InkWell(
            onTap: () => widget.onChanged((minutes + delta + 1440) % 1440),
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 110,
              child: Center(child: Text(minutesText(minutes + delta), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: Ob.faint))),
            ),
          ),
        );
    Widget arrow(bool left) => AnimatedBuilder(
          animation: _nudge,
          builder: (_, child) => Transform.translate(offset: Offset((left ? -7 : 7) * Curves.easeInOut.transform(1 - (2 * _nudge.value - 1).abs()), 0), child: child),
          child: Icon(left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 40, color: Ob.accent),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Ob.muted)),
        const SizedBox(height: 14),
        Listener(
          onPointerDown: (_) => _nudge.stop(),
          child: SwipeAdjust(
            value: minutes,
            wrap: 1440,
            onChanged: widget.onChanged,
            child: Container(
              height: 110,
              decoration: BoxDecoration(color: Ob.chip, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  side(-10),
                  arrow(true),
                  Container(
                    width: 170,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Ob.accentTint, borderRadius: BorderRadius.circular(14), border: Border.all(color: Ob.accent, width: 2)),
                    child: Text(minutesText(minutes), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Ob.text)),
                  ),
                  arrow(false),
                  side(10),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;

  const _DayChip(this.label, {required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? Colors.white : Ob.chip,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 80,
          height: 74,
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: on ? Ob.ink : Ob.faint)),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String name;
  final bool on;
  final bool green;
  final VoidCallback? onTap;

  const _Row({required this.icon, required this.name, required this.on, this.green = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tint = green ? Ob.greenTint : Ob.accentTint;
    final color = green ? Ob.green : Ob.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: on ? tint : Ob.chip,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 72,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: [
                  Icon(icon, size: 28, color: on ? color : Ob.faint),
                  const SizedBox(width: 16),
                  Expanded(child: Text(name, style: Ob.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (on) ObCheck(size: 30, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final IconData icon;
  final String title, value;

  const _Summary({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Ob.card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 34, color: Ob.accent),
          const Spacer(),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Ob.text)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Ob.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _CancelButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      height: 80,
      child: Material(
        color: onTap == null ? Ob.chip : Ob.navyConnector,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close_rounded, size: 26, color: Colors.white),
              SizedBox(width: 10),
              Text('등록 취소', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 취소를 고르면 true
class _CancelDialog extends StatelessWidget {
  const _CancelDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Ob.dialog,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SizedBox(
        width: 760,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 44, 48, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 52, color: Ob.red),
              const SizedBox(height: 14),
              const Text('등록을 취소할까요?', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Ob.text)),
              const SizedBox(height: 14),
              const Text('지금까지 입력한 이름 · 얼굴 · PIN · 생활 패턴이 모두 지워지고\n처음 화면으로 돌아가요.',
                  style: TextStyle(fontSize: 22, color: Ob.muted, height: 1.45)),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(child: _DialogButton('계속 등록하기', onTap: () => Navigator.pop(context, false))),
                  const SizedBox(width: 14),
                  Expanded(child: _DialogButton('등록 취소', danger: true, onTap: () => Navigator.pop(context, true))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final bool danger;
  final VoidCallback onTap;

  const _DialogButton(this.label, {required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Material(
        color: danger ? Ob.red : Ob.navyCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: danger ? Colors.white : Ob.text)),
          ),
        ),
      ),
    );
  }
}
