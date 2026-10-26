part of '../checklist_screen.dart';

class _Thing {
  const _Thing({required this.name, required this.sub, required this.icon, this.subColor = _D.faint, this.subNames, this.dim = false, this.onTap});

  final String name;
  final String sub;

  /// 있으면 [sub] 대신 이름을 사람 색으로 보인다
  final List<(String, Color)>? subNames;
  final IconData icon;
  final Color subColor;
  final bool dim;
  final VoidCallback? onTap;
}

class _LowerCard extends StatelessWidget {
  const _LowerCard({required this.title, required this.count, required this.things, required this.extra, required this.appliances, this.onTap, this.onLongPress});

  final String title;
  final String count;
  final List<_Thing> things;

  /// 칸이 모자라 못 보인 물건 수
  final int extra;
  final List<ApplianceViewData> appliances;
  final ValueChanged<String>? onTap;
  final ValueChanged<String>? onLongPress;

  @override
  Widget build(BuildContext context) {
    // 왼쪽 열은 Shelly 2개, 오른쪽 2×2 는 ThinQ
    final shelly = appliances.where((a) => !a.thinq).take(2).toList();
    final thinq = appliances.where((a) => a.thinq).take(4).toList();
    Widget slot(ApplianceViewData? a) => a == null
        ? const SizedBox.shrink()
        : _ApplianceTile(a, onTap: onTap == null ? null : () => onTap!(a.id), onLongPress: a.thinq && onLongPress != null ? () => onLongPress!(a.id) : null);
    final on = appliances.where((a) => a.isOn || a.alert).length;
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Head(title, trailing: count),
                const SizedBox(height: 18),
                Expanded(child: _Grid(columns: 4, extra: extra, children: [for (final t in things) _ThingTile(t)])),
              ],
            ),
          ),
          Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 32), color: _D.line),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Head('집 상태', trailing: appliances.isEmpty ? null : (on > 0 ? '확인 필요 $on' : '모두 꺼짐'), trailingColor: on > 0 ? _D.red : _D.green),
                const SizedBox(height: 18),
                Expanded(
                  child: appliances.isEmpty
                      ? Center(child: Text('가전 없음', style: _D.t(19, c: _D.faint)))
                      : _Grid(
                          columns: 3,
                          children: [
                            slot(shelly.elementAtOrNull(0)), slot(thinq.elementAtOrNull(0)), slot(thinq.elementAtOrNull(1)),
                            slot(shelly.elementAtOrNull(1)), slot(thinq.elementAtOrNull(2)), slot(thinq.elementAtOrNull(3)),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children, this.extra = 0});

  final int columns;
  final List<Widget> children;
  final int extra;

  @override
  Widget build(BuildContext context) {
    Widget row(int r) => Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < columns; c++)
                Expanded(child: r * columns + c < children.length ? children[r * columns + c] : const SizedBox.shrink()),
            ],
          ),
        );
    return Stack(
      children: [
        Column(
          children: [
            row(0),
            Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 14), color: _D.line),
            row(1),
          ],
        ),
        if (extra > 0) Positioned(right: 0, bottom: 0, child: Text('외 $extra개', style: _D.t(14, c: _D.faint))),
      ],
    );
  }
}

class _ThingTile extends StatelessWidget {
  const _ThingTile(this.t);

  final _Thing t;

  @override
  Widget build(BuildContext context) {
    final fg = t.dim ? _D.dim : Colors.white;
    return Semantics(
      button: t.onTap != null,
      label: '${t.name}, ${t.sub}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: t.onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 22, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(t.icon, size: 52, color: fg),
              const Spacer(),
              Text(t.name, style: _D.t(22, w: FontWeight.w600, c: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              if (t.subNames case final names?)
                Text.rich(
                  TextSpan(children: [
                    for (var i = 0; i < names.length; i++) ...[
                      if (i > 0) TextSpan(text: ' · ', style: _D.t(14, c: _D.faint)),
                      TextSpan(text: names[i].$1, style: _D.t(14, w: FontWeight.w600, c: _D.nameColor(names[i].$2))),
                    ],
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              else
                Text(t.sub, style: _D.t(14, c: t.subColor, w: t.subColor == _D.faint ? FontWeight.w400 : FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplianceTile extends StatelessWidget {
  const _ApplianceTile(this.a, {this.onTap, this.onLongPress});

  final ApplianceViewData a;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final (status, color) = a.errorMessage != null
        ? ('끄기 실패', _D.orange)
        : a.status != null
            ? (a.status!, a.alert ? _D.orange : _D.faint)
            : a.isOn
            ? ('작동 중 · ${a.currentAmp.toStringAsFixed(1)}A', _D.red)
            : ('꺼짐', _D.faint);
    // Shelly 는 전류가 없어도 릴레이가 켜져 있으면 켜짐으로 본다
    final on = a.isOn || (a.thinq ? a.alert : a.plugOn);
    final accent = a.thinq ? _D.orange : _D.red;
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Material(
        color: on ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: a.isBusy ? null : onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(a.icon, size: 50, color: on ? accent : Colors.white),
                    const Spacer(),
                    if (a.isBusy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                  ],
                ),
                const Spacer(),
                Text(a.name, style: _D.t(22, w: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${a.room.isEmpty || a.status != null ? '' : '${a.room} · '}$status', style: _D.t(14, c: color), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
