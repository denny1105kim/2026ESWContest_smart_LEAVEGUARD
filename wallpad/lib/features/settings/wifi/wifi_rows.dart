part of 'wifi_pane.dart';

Widget _switch(bool on, ValueChanged<bool>? onChanged) => Switch(
      value: on,
      onChanged: onChanged,
      activeTrackColor: Palette.accent,
      inactiveTrackColor: Palette.line,
      inactiveThumbColor: Colors.white,
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    );

IconData _bars(int n) => switch (n) {
      3 => Icons.wifi_rounded,
      2 => Icons.wifi_2_bar_rounded,
      _ => Icons.wifi_1_bar_rounded,
    };

class _ConnectedCard extends StatelessWidget {
  final WifiNetwork n;
  final VoidCallback onTap;

  const _ConnectedCard(this.n, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Space.l + 4),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.card),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Palette.soft(Palette.accent), shape: BoxShape.circle),
                child: Icon(_bars(n.bars), color: Palette.accent),
              ),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(n.name, style: Txt.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: Space.s),
                        const StatusTag('연결됨', color: Palette.done),
                      ],
                    ),
                    Text('신호 ${n.signal} · ${n.staticIp ? '고정' : ''} IP ${n.ipv4.address}', style: Txt.sub),
                  ],
                ),
              ),
              Text('상세', style: Txt.sub.copyWith(color: Palette.accent, fontWeight: FontWeight.w600)),
              const Icon(Icons.chevron_right_rounded, color: Palette.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  final WifiNetwork n;
  final VoidCallback onTap;

  const _NetworkRow(this.n, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.button),
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: Space.m),
            Icon(_bars(n.bars), color: Palette.text, size: 24),
            const SizedBox(width: Space.l),
            Expanded(child: Text(n.name, style: Txt.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (n.busy) ...[const Text('연결 중…', style: Txt.caption), const SizedBox(width: Space.m)],
            if (!n.supported) ...[const StatusTag('지원 안 함', color: Palette.faint), const SizedBox(width: Space.m)],
            if (n.saved) ...[const StatusTag('저장됨', color: Palette.accent), const SizedBox(width: Space.m)],
            if (!n.open) const Icon(Icons.lock_rounded, color: Palette.faint, size: 18),
            const SizedBox(width: Space.m),
            const Icon(Icons.chevron_right_rounded, color: Palette.faint),
            const SizedBox(width: Space.s),
          ],
        ),
      ),
    );
  }
}

class _PowerSwitch extends StatelessWidget {
  final bool on;
  final ValueChanged<bool>? onChanged;

  const _PowerSwitch({required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kTouch,
      padding: const EdgeInsets.only(left: Space.l, right: Space.xs),
      decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.button), border: Border.all(color: Palette.line)),
      child: Row(
        children: [
          Text(on ? '켜짐' : '꺼짐', style: Txt.button.copyWith(color: on ? Palette.accent : Palette.muted)),
          _switch(on, onChanged),
        ],
      ),
    );
  }
}
