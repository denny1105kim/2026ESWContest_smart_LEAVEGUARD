import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/design_canvas.dart';
import 'thinq_sim.dart';

/// 가전 켜기·끄기와 로봇청소기 자동 청소 시각
class ApplianceControls extends StatelessWidget {
  const ApplianceControls({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final sim = ThinqSim.instance;
    return ListenableBuilder(
      listenable: sim,
      builder: (context, _) {
        final d = sim.byId(id);
        if (d == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(d.status, style: Txt.title.copyWith(fontSize: 24))),
                AppButton(d.tone == ThinqTone.done ? '꺼냈어요' : d.isOn ? (d.isRobot ? '청소 멈춤' : '끄기') : (d.isRobot ? '지금 청소' : '켜기'), height: 48, onPressed: () => sim.togglePower(id)),
              ],
            ),
            if (d.isRobot) ...[
              const SizedBox(height: Space.l),
              const Text('매일 자동 청소', style: Txt.bodyStrong),
              const SizedBox(height: Space.s),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  _chip('끔', d.cleanAt == null, () => sim.setCleanAt(id, null)),
                  for (final t in ThinqSim.cleanTimes) _chip(t, d.cleanAt == t, () => sim.setCleanAt(id, t)),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  static Widget _chip(String label, bool on, VoidCallback onTap) => Material(
        color: on ? Colors.white : Palette.raised,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(label, style: Txt.bodyStrong.copyWith(fontSize: 17, color: on ? Palette.ink : Palette.text)),
          ),
        ),
      );
}

Future<void> showApplianceSheet(BuildContext context, String id) {
  final d = ThinqSim.instance.byId(id);
  if (d == null) return Future.value();
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xFF101322).withValues(alpha: 0.55),
    builder: (context) => DesignCanvas.legacy(
      child: Center(
        child: Material(
          color: Palette.dialog,
          borderRadius: BorderRadius.circular(Radii.card),
          child: SizedBox(
            width: 480,
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('${d.kind} · ${d.name}', style: Txt.sub, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      RoundIconButton(Icons.close_rounded, size: 44, background: Palette.raised, onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: Space.s),
                  ApplianceControls(id: id),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
