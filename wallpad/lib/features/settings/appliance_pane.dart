import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/tags.dart';
import '../appliances/appliance_sheet.dart';
import '../appliances/thinq_sim.dart';
import 'settings_screen.dart';

/// ThinQ 가전 연결 (시뮬레이션). 집 공통 목록이라 사용자와 무관하다
class AppliancePane extends StatefulWidget {
  const AppliancePane({super.key});

  @override
  State<AppliancePane> createState() => _AppliancePaneState();
}

enum _Step { list, kinds, found, detail }

class _AppliancePaneState extends State<AppliancePane> {
  final sim = ThinqSim.instance;
  var _step = _Step.list;
  String _kind = '세탁기';
  String? _deviceId;

  void _go(_Step s) => setState(() => _step = s);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sim,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(
          key: ValueKey(_step),
          child: switch (_step) {
            _Step.list => _list(),
            _Step.kinds => _kinds(),
            _Step.found => _found(),
            _Step.detail => _detail(),
          },
        ),
      ),
    );
  }

  Widget _list() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaneHeader(title: '가전 연결', subtitle: 'LG ThinQ · 메인 화면 ${sim.mainDevices.length}/${ThinqSim.mainMax}', action: AppButton('가전 추가', icon: Icons.add_rounded, onPressed: () => _go(_Step.kinds))),
          const SizedBox(height: Space.l),
          Expanded(
            child: _Card(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: sim.devices.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Palette.line),
                itemBuilder: (context, i) {
                  final d = sim.devices[i];
                  return _Row(
                    lead: _Letter(d.initial, tone: d.tone),
                    title: '${d.kind} · ${d.name}',
                    sub: '${d.status} · ${d.room}',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (d.onMain) ...[const StatusTag('메인', color: Palette.accent), const SizedBox(width: Space.s)],
                      _toneTag(d.tone),
                      const SizedBox(width: Space.s),
                      const Icon(Icons.chevron_right_rounded, color: Palette.faint),
                    ]),
                    onTap: () => setState(() {
                      _deviceId = d.id;
                      _step = _Step.detail;
                    }),
                  );
                },
              ),
            ),
          ),
        ],
      );

  Widget _kinds() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaneHeader(title: '가전 추가', onBack: () => _go(_Step.list)),
          const SizedBox(height: Space.l),
          GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            mainAxisSpacing: Space.m,
            crossAxisSpacing: Space.m,
            childAspectRatio: 1.15,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final k in ThinqSim.kinds)
                Material(
                  color: Palette.surface,
                  borderRadius: BorderRadius.circular(Radii.card),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => setState(() {
                      _kind = k;
                      _step = _Step.found;
                    }),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [_Letter(k.characters.first), const SizedBox(height: Space.s), Text(k, style: Txt.bodyStrong.copyWith(fontSize: 16))],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.m),
          _Card(
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
            child: Row(children: [
              const Text('그 외 20종', style: Txt.bodyStrong),
              const SizedBox(width: Space.m),
              const Expanded(child: Text(ThinqSim.otherKinds, style: Txt.sub, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ],
      );

  Widget _found() {
    final found = sim.foundFor(_kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(title: 'ThinQ 에서 찾은 가전', subtitle: _kind, onBack: () => _go(_Step.kinds)),
        const SizedBox(height: Space.l),
        _Card(
          child: Column(children: [
            for (var i = 0; i < found.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Palette.line),
              Opacity(
                opacity: found[i].online ? 1 : 0.5,
                child: _Row(
                  lead: _Letter(found[i].name.characters.first),
                  title: found[i].name,
                  sub: found[i].online ? '${found[i].model} · ${found[i].room} · 온라인' : '${found[i].model} · 오프라인 ${found[i].offlineDays}일',
                  trailing: AppButton('추가',
                      height: 48,
                      onPressed: found[i].online
                          ? () {
                              sim.add(_kind, found[i]);
                              _go(_Step.list);
                            }
                          : null),
                ),
              ),
            ],
          ]),
        ),
        const SizedBox(height: Space.m),
        _Card(
          padding: const EdgeInsets.all(Space.l),
          child: Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ThinQ 계정 연결', style: Txt.bodyStrong),
              ]),
            ),
            AppButton.ghost('QR 로 연결', height: 48, onPressed: () {}),
          ]),
        ),
      ],
    );
  }

  Widget _detail() {
    final d = sim.devices.where((d) => d.id == _deviceId).firstOrNull;
    if (d == null) return _list();
    const alerts = [
      ('외출할 때 작동 중이면 알림', '외출'),
      ('끝나고 안 꺼냈으면 알림', '귀가 · 아침'),
      ('밤에 돌렸으면 다음 날 알림', '22시 이후'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(
          title: '${d.kind} · ${d.name}',
          subtitle: '${d.room} · ${d.model}',
          onBack: () => _go(_Step.list),
          action: AppButton.ghost('연결 끊기', height: 48, onPressed: () {
            sim.remove(d.id);
            _go(_Step.list);
          }),
        ),
        const SizedBox(height: Space.l),
        _Card(padding: const EdgeInsets.all(Space.l), child: ApplianceControls(id: d.id)),
        const SizedBox(height: Space.m),
        _Card(
          child: _Row(
            title: '메인 화면에 표시',
            sub: '최대 ${ThinqSim.mainMax}개 · 지금 ${sim.mainDevices.length}개',
            trailing: Switch(value: d.onMain, activeTrackColor: Palette.accent, onChanged: (v) => sim.setOnMain(d.id, v)),
          ),
        ),
        const SizedBox(height: Space.l),
        const Text('알림', style: Txt.bodyStrong),
        const SizedBox(height: Space.s),
        _Card(
          child: Column(children: [
            for (var i = 0; i < alerts.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Palette.line),
              _Row(title: alerts[i].$1, sub: alerts[i].$2, trailing: Switch(value: d.alerts[i], activeTrackColor: Palette.done, onChanged: (_) => sim.toggleAlert(d.id, i))),
            ],
          ]),
        ),
      ],
    );
  }

  static Widget _toneTag(ThinqTone t) => switch (t) {
        ThinqTone.running => const StatusTag('돌아가는 중', color: Palette.warn),
        ThinqTone.done => const StatusTag('끝남', color: Palette.done),
        ThinqTone.idle => const StatusTag('대기', color: Palette.muted),
        ThinqTone.off => const StatusTag('꺼짐', color: Palette.faint),
      };
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card)),
        child: child,
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.sub, this.lead, this.trailing, this.onTap});

  final String title, sub;
  final Widget? lead, trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
          child: Row(children: [
            if (lead != null) ...[lead!, const SizedBox(width: Space.m)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Txt.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(sub, style: Txt.sub.copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: Space.m), trailing!],
          ]),
        ),
      );
}

class _Letter extends StatelessWidget {
  const _Letter(this.ch, {this.tone});

  final String ch;
  final ThinqTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = switch (tone) { ThinqTone.running => Palette.warn, ThinqTone.done => Palette.done, _ => Colors.white };
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tone == null || c == Colors.white ? Palette.raised : Palette.soft(c), shape: BoxShape.circle),
      child: Text(ch, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c)),
    );
  }
}
