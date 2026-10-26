import 'dart:math';

import 'package:flutter/material.dart';

import '../../device/camera/camera_session.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/camera_preview.dart';
import '../../core/config/scan_config.dart';
import '../../core/config/constants.dart';
import '../../app/app_state.dart';
import '../../app/backend.dart';
import '../../core/theme/tokens.dart';
import '../../device/camera/vision.dart';

class IdentifyingScreen extends StatefulWidget {
  const IdentifyingScreen({super.key});

  @override
  State<IdentifyingScreen> createState() => _IdentifyingScreenState();
}

class _IdentifyingScreenState extends State<IdentifyingScreen> with TickerProviderStateMixin, CameraSession {
  late final _countdown = AnimationController(vsync: this, duration: identifyTimeout)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) app.faceFailed();
    })
    ..forward();
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  final _hits = <int, int>{};
  String? _hint;

  @override
  void initState() {
    super.initState();
    openCamera('scan');
  }

  @override
  void onVision(VisionEvent e) {
    switch (e.type) {
      case 'face':
        _check(e.embedding);
      case 'many':
        _say('한 명만');
      case 'poor':
        _say('정면');
      case 'none':
        _say(null);
    }
  }

  @override
  void cameraFailed() => _say('카메라 없음');

  void _say(String? hint) {
    if (hint != _hint) setState(() => _hint = hint);
  }

  Future<void> _check(List<double> embedding) async {
    final member = await repo.findMemberByEmbedding(embedding,
        threshold: ScanConfig.threshold, margin: ScanConfig.margin);
    if (member == null || !watching) return;
    final hits = _hits[member.id] = (_hits[member.id] ?? 0) + 1;
    if (hits < ScanConfig.confirmFrames) return;
    closeCamera();
    app.faceSucceeded('${member.id}');
  }

  @override
  void dispose() {
    _countdown.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    watch(context);
    final greeting = app.userOf(app.greetingUserId);
    if (greeting != null) _countdown.stop();

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          const SizedBox(height: 44),
          SizedBox.square(
            dimension: 300,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CameraPreviewBox(width: 272, height: 272, circle: true, frame: frame),
                AnimatedBuilder(
                  animation: _spin,
                  builder: (_, __) => CustomPaint(
                    size: const Size.square(300),
                    painter: _RingPainter(turn: _spin.value, locked: greeting != null),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xl),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: greeting != null
                ? Column(
                    key: const ValueKey('hi'),
                    children: [
                      Text('${greeting.name}님', style: Txt.hero),
                    ],
                  )
                : Column(
                    key: const ValueKey('scan'),
                    children: [
                      const Text('얼굴 인식 중', style: Txt.title),
                      const SizedBox(height: Space.s),
                      Text(_hint ?? '', style: Txt.sub),
                    ],
                  ),
          ),
          const Spacer(),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: greeting == null ? 1 : 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(96, 0, 96, Space.xxl),
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _countdown,
                      builder: (_, __) {
                        final left = 1 - _countdown.value;
                        final seconds = (left * identifyTimeout.inSeconds).ceil();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$seconds초', style: Txt.caption),
                            const SizedBox(height: Space.s),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(Radii.pill),
                              child: LinearProgressIndicator(
                                value: left,
                                minHeight: 6,
                                backgroundColor: Palette.raised,
                                color: Palette.accent,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: Space.xl),
                  AppButton.ghost('직접 선택', icon: Icons.people_alt_rounded, onPressed: () => app.go(Stage.userSelect)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double turn;
  final bool locked;

  _RingPainter({required this.turn, required this.locked});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = Colors.white.withValues(alpha: 0.25);
    canvas.drawCircle(rect.center, size.width / 2 - 4, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final r = rect.deflate(4);
    if (locked) {
      canvas.drawArc(r, 0, 2 * pi, false, arc..color = Palette.done);
    } else {
      arc.shader = SweepGradient(
        colors: [Palette.accent.withValues(alpha: 0), Palette.accent, const Color(0xFF8C7BFF)],
        stops: const [0, 0.7, 1],
        transform: GradientRotation(turn * 2 * pi),
      ).createShader(r);
      canvas.drawArc(r, turn * 2 * pi, pi * 0.9, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.turn != turn || old.locked != locked;
}
