part of '../checklist_screen.dart';

class _MemoPopup extends StatelessWidget {
  const _MemoPopup({required this.lines, required this.onConfirm});

  final List<String> lines;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x99101322),
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: WallpadTokens.modalTransition,
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(opacity: t, child: Transform.scale(scale: 0.96 + 0.04 * t, child: child)),
        child: Container(
          width: 860,
          padding: const EdgeInsets.fromLTRB(48, 44, 48, 44),
          decoration: BoxDecoration(
            color: WallpadTokens.surfaceSolid,
            borderRadius: BorderRadius.circular(36),
            boxShadow: const [BoxShadow(color: Color(0x66101322), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: const Color(0x33FFC857), borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.edit_note_rounded, size: 34, color: Color(0xFFFFC857)),
                ),
                const SizedBox(width: 20),
                Text('어젯밤 메모', style: _D.t(34, w: FontWeight.w700, h: 1.2)),
              ]),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.fromLTRB(32, 22, 32, 22),
                decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(24)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final l in lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(children: [
                          Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 18), decoration: const BoxDecoration(color: Color(0xFFFFC857), shape: BoxShape.circle)),
                          Expanded(child: Text(l, style: _D.t(30, w: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Align(alignment: Alignment.centerRight, child: SizedBox(width: 240, child: _WhiteButton(label: '확인', onPressed: onConfirm, height: 72))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dialog extends StatelessWidget {
  const _Dialog({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // 뒤 화면이 눌리지 않게
        child: ColoredBox(
          color: const Color(0x990B0F1E),
          child: Center(
            child: Container(
              padding: const EdgeInsets.fromLTRB(56, 48, 56, 44),
              decoration: BoxDecoration(color: const Color(0xFA2B3152), borderRadius: BorderRadius.circular(32)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupPick extends StatelessWidget {
  const _GroupPick({required this.pick, this.onToggle, this.onConfirm, this.onCancel});

  final GroupPickViewData pick;
  final ValueChanged<String>? onToggle;
  final VoidCallback? onConfirm, onCancel;

  @override
  Widget build(BuildContext context) {
    final n = pick.picked.length + 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('누구와 함께 나가요?', style: _D.t(34, w: FontWeight.w600)),
        const SizedBox(height: 36),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _card(pick.meName, pick.meColor, on: true, sub: '나'),
            for (final (id, name, color) in pick.candidates)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle == null ? null : () => onToggle!(id),
                child: _card(name, color, on: pick.picked.contains(id), sub: pick.picked.contains(id) ? '함께' : '누르면 함께'),
              ),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 200, child: _SoftButton(label: '취소', onPressed: onCancel ?? () {})),
            const SizedBox(width: 14),
            SizedBox(width: 260, child: _WhiteButton(label: '함께 외출 · $n명', height: 64, onPressed: n < 2 ? null : onConfirm)),
          ],
        ),
      ],
    );
  }

  Widget _card(String name, Color color, {required bool on, required String sub}) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;
    return Opacity(
      opacity: on ? 1 : 0.55,
      child: Container(
        width: 176,
        padding: const EdgeInsets.fromLTRB(12, 26, 12, 22),
        decoration: BoxDecoration(
          color: on ? const Color(0x1AFFFFFF) : const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: on ? const Color(0xD9FFFFFF) : const Color(0x1FFFFFFF), width: on ? 2 : 1),
        ),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              child: Text(initial, style: _D.t(34, w: FontWeight.w600, h: 1)),
            ),
            const SizedBox(height: 12),
            Text(name, style: _D.t(24, w: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (on && sub == '함께') ...[const Icon(Icons.check_rounded, size: 20, color: _D.green), const SizedBox(width: 4)],
                Text(sub, style: _D.t(15, c: const Color(0xA6FFFFFF))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Ask extends StatelessWidget {
  const _Ask({required this.title, required this.detail, required this.keep, required this.stop, this.onKeep, this.onStop});

  final String title, detail, keep, stop;
  final VoidCallback? onKeep, onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: _D.t(34, w: FontWeight.w600)),
        const SizedBox(height: 12),
        Text(detail, style: _D.t(18, c: _D.faint)),
        const SizedBox(height: 32),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 200, child: _SoftButton(label: keep, onPressed: onKeep ?? () {})),
            const SizedBox(width: 14),
            SizedBox(width: 200, child: _WhiteButton(label: stop, height: 64, onPressed: onStop)),
          ],
        ),
      ],
    );
  }
}
