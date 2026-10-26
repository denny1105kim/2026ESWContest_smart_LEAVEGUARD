import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../app/backend.dart' show onBoard;
import '../../app/models.dart';
import '../../core/config/constants.dart';
import '../../core/theme/wallpad_tokens.dart';
import '../../shared/widgets/design_canvas.dart';
import '../../shared/time_text.dart';

/// 현관 카메라 팝업: 대기 중엔 상태 칩, 사람이 오면 라이브 박스, 다른 화면을 쓰는 중이면 작은 창.
class DoorCamOverlay extends StatelessWidget {
  const DoorCamOverlay({super.key});

  // ESP32-CAM VGA
  static const frameSize = Size(640, 480);

  @override
  Widget build(BuildContext context) {
    final app = watch(context);
    final Widget? child;
    if (app.doorPhase == DoorPhase.idle) {
      child = app.stage == Stage.idle && onBoard ? const Positioned(right: 64, bottom: 150, child: _StatusChip()) : null;
    } else if (!app.doorBusyScreen) {
      child = const Positioned(left: 400, top: 110, child: _LiveBox());
    } else {
      child = const Positioned(right: 64, top: 120, child: _Pip());
    }
    if (child == null) return const SizedBox.shrink();
    return Positioned.fill(
      // 위에 따로 떠 있어 Material 이 없으면 글씨에 디버그 밑줄이 생긴다
      child: Material(type: MaterialType.transparency, child: DesignCanvas.fitWidth(child: Stack(children: [child]))),
    );
  }

  /// BoxFit.cover 로 보일 때 프레임 기준 0~1 박스 [n] 의 칸 안 위치. [frame] 은 돌린 뒤 크기.
  static Rect coverRect(Size box, Rect n, [Size frame = frameSize]) {
    final scale = max(box.width / frame.width, box.height / frame.height);
    final w = frame.width * scale, h = frame.height * scale;
    final ox = (box.width - w) / 2, oy = (box.height - h) / 2;
    return Rect.fromLTWH(ox + n.left * w, oy + n.top * h, n.width * w, n.height * h);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip();

  @override
  Widget build(BuildContext context) {
    final app = watch(context);
    final (dot, text) = !app.doorOnline
        ? (WallpadTokens.danger, '현관 카메라 · 연결 안 됨')
        : app.doorFaceFrames > 0
            ? (WallpadTokens.warning, '현관 카메라 · 얼굴 감지 중 ${min(app.doorFaceFrames, doorFaceNeeded)} / $doorFaceNeeded장')
            : (WallpadTokens.success, '현관 카메라 · 지켜보는 중');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(color: WallpadTokens.surfaceSolid, borderRadius: BorderRadius.circular(WallpadTokens.radiusPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(dot),
          const SizedBox(width: 12),
          Text(text, style: WallpadTokens.body.copyWith(color: const Color(0xFFD5DAE4), fontSize: 20)),
        ],
      ),
    );
  }
}

class _LiveBox extends StatelessWidget {
  const _LiveBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1120,
      height: 760,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E27),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 60, offset: Offset(0, 20))],
      ),
      child: const Column(
        children: [
          SizedBox(height: 600, child: _Video(size: Size(1120, 600))),
          Expanded(child: _Band()),
        ],
      ),
    );
  }
}

class _Video extends StatelessWidget {
  const _Video({required this.size, this.compact = false});

  final Size size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = watch(context);
    final frame = app.doorFrame;
    final box = app.doorFaceBox;
    final phase = app.doorPhase;
    final (boxColor, dashed) = switch (phase) {
      DoorPhase.known => (WallpadTokens.success, false),
      DoorPhase.unknown => (WallpadTokens.danger, false),
      _ => (WallpadTokens.warning, true),
    };
    final pad = compact ? 12.0 : 24.0;
    // 카메라가 돌아 달렸으면 vision 이 알려 준 만큼 돌린다
    final quarter = app.doorRotation ~/ 90;
    final shown = quarter.isOdd ? Size(DoorCamOverlay.frameSize.height, DoorCamOverlay.frameSize.width) : DoorCamOverlay.frameSize;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (frame != null)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: RotatedBox(
              quarterTurns: quarter,
              child: Image.memory(frame, width: DoorCamOverlay.frameSize.width, height: DoorCamOverlay.frameSize.height, gaplessPlayback: true, filterQuality: FilterQuality.medium),
            ),
          )
        else
          const DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2B2F3B), Color(0xFF1B1E27)])),
            child: Center(child: Icon(Icons.videocam_off_rounded, size: 72, color: Color(0xFF59607A))),
          ),
        if (box != null)
          Positioned.fromRect(
            rect: DoorCamOverlay.coverRect(size, box, shown).inflate(compact ? 6 : 16),
            child: CustomPaint(painter: _FaceBoxPainter(boxColor, dashed: dashed, width: compact ? 3 : 4)),
          ),
        Positioned(left: pad, top: pad, child: _Pill('LIVE · 현관', bg: WallpadTokens.danger, dot: Colors.white, small: compact)),
        Positioned(
          right: pad,
          top: pad,
          child: Row(
            children: [
              if (!compact && phase == DoorPhase.unknown && !app.doorOpened) ...[
                _Pill('저장 중 ${mmss(Duration(seconds: doorUnknownHold - app.doorSecondsLeft))} / ${mmss(const Duration(seconds: doorUnknownHold))}', bg: const Color(0x33FFFFFF), dot: Colors.white),
                const SizedBox(width: 12),
              ],
              _CloseButton(size: compact ? 40 : 56, onTap: app.doorDismiss),
            ],
          ),
        ),
        if (!compact)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: switch (phase) {
                // 도어락이 닫힌 뒤 1초 있다가 귀가 화면으로 넘어간다
                DoorPhase.known => _Pill(app.doorSecondsLeft > 1 ? '문이 열렸어요 · ${app.doorSecondsLeft - 1}초 뒤 닫혀요' : '문이 닫혔어요',
                    bg: const Color(0xFFE6F6EE), fg: WallpadTokens.ink, dot: WallpadTokens.success),
                DoorPhase.unknown => _Pill(app.doorSpoofed ? '실제 얼굴로 보이지 않아요' : '등록되지 않은 사람이에요', bg: const Color(0xFFFDECEC), fg: WallpadTokens.ink, dot: WallpadTokens.danger),
                _ => _Pill('얼굴을 확인하고 있어요 …', bg: const Color(0xFFFFF2E3), fg: WallpadTokens.ink, dot: WallpadTokens.warning),
              },
            ),
          ),
      ],
    );
  }
}

class _Band extends StatelessWidget {
  const _Band();

  @override
  Widget build(BuildContext context) {
    final app = watch(context);
    final user = app.userOf(app.doorUserId);
    final title = WallpadTokens.sectionTitle;
    final sub = WallpadTokens.secondary;
    final Widget body;
    switch (app.doorPhase) {
      case DoorPhase.known:
        body = Row(
          children: [
            if (user != null) ...[_Avatar(user), const SizedBox(width: 20)],
            Expanded(child: Text('${user?.name ?? ''}님, 어서 오세요', style: title)),
          ],
        );
      case DoorPhase.unknown:
        body = Row(
          children: [
            Expanded(child: Text(app.doorOpened ? '문을 열었어요' : app.doorSpoofed ? '현관에 사진이나 화면이 보여요' : '현관에 모르는 사람이 있어요', style: title)),
            if (!app.doorOpened) ...[
              OutlinedButton(onPressed: app.doorDismiss, child: const Text('무시')),
              const SizedBox(width: 16),
              FilledButton.icon(onPressed: app.doorOpen, icon: const Icon(Icons.lock_open_rounded), label: const Text('문 열기')),
            ],
          ],
        );
      default:
        body = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('현관에 누군가 있어요', style: title),
            const SizedBox(height: 6),
            Text('등록된 가족인지 확인하는 중', style: sub),
          ],
        );
    }
    return ColoredBox(
      color: WallpadTokens.surfaceSolid,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: body),
    );
  }
}

class _Pip extends StatelessWidget {
  const _Pip();

  @override
  Widget build(BuildContext context) {
    final app = watch(context);
    final (title, sub) = switch (app.doorPhase) {
      DoorPhase.known => ('${app.userOf(app.doorUserId)?.name ?? ''}님, 어서 오세요', null),
      DoorPhase.unknown => (app.doorSpoofed ? '현관에 사진이나 화면이 보여요' : '현관에 모르는 사람이 있어요', null),
      _ => ('현관에 누군가 있어요', '등록된 가족인지 확인하는 중'),
    };
    return Container(
      width: 480,
      height: 340,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E27),
        borderRadius: BorderRadius.circular(WallpadTokens.radiusLg),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 40, offset: Offset(0, 12))],
      ),
      child: Column(
        children: [
          const SizedBox(height: 270, child: _Video(size: Size(480, 270), compact: true)),
          Expanded(
            child: ColoredBox(
              color: WallpadTokens.surfaceSolid,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: WallpadTokens.bodyMedium.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (sub != null) ...[
                            const SizedBox(height: 2),
                            Text(sub, style: WallpadTokens.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ],
                      ),
                    ),
                    if (app.doorOffersReturn) ...[
                      const SizedBox(width: 12),
                      Material(
                        color: Colors.white,
                        shape: const StadiumBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: app.doorOpenReturn,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            child: Text('귀가 화면 열기 · ${app.doorSecondsLeft}',
                                style: WallpadTokens.bodyMedium.copyWith(color: WallpadTokens.ink, fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.bg, this.fg = Colors.white, this.dot, this.small = false});

  final String text;
  final Color bg, fg;
  final Color? dot;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 12 : 18, vertical: small ? 6 : 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(WallpadTokens.radiusPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[_Dot(dot!, size: small ? 8 : 10), SizedBox(width: small ? 6 : 10)],
          Text(text, style: WallpadTokens.bodyMedium.copyWith(color: fg, fontSize: small ? 15 : 19, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color, {this.size = 12});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x66000000),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(dimension: size, child: Icon(Icons.close_rounded, color: Colors.white, size: size * 0.5)),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.user);

  final User user;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: user.color, shape: BoxShape.circle),
      child: Text(user.initial, style: WallpadTokens.cardPrimary.copyWith(color: Colors.white)),
    );
  }
}

class _FaceBoxPainter extends CustomPainter {
  const _FaceBoxPainter(this.color, {required this.dashed, required this.width});

  final Color color;
  final bool dashed;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    if (!dashed) return canvas.drawRRect(rrect, paint);
    const dash = 14.0, gap = 10.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, min(d + dash, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_FaceBoxPainter old) => old.color != color || old.dashed != dashed || old.width != width;
}
