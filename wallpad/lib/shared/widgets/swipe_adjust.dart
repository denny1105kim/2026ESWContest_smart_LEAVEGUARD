import 'dart:math';

import 'package:flutter/material.dart';

/// [child] 를 좌우로 밀어 값을 바꾼다. 왼쪽으로 밀면 커지고, 빠를수록 많이 넘어간다.
class SwipeAdjust extends StatefulWidget {
  const SwipeAdjust({
    super.key,
    required this.value,
    required this.onChanged,
    required this.child,
    this.step = 10,
    this.stepWidth = 40,
    this.wrap,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final Widget child;

  final int step;
  final double stepWidth; // 천천히 밀 때 한 칸 거리(px)
  final int? wrap; // 0 ≤ 값 < wrap 에서 돈다

  static const slowSpeed = 0.35; // px/ms, 이하면 1배
  static const maxGain = 4.0;

  static double gainFor(double pxPerMs) => pxPerMs <= slowSpeed ? 1 : min(maxGain, 1 + (pxPerMs - slowSpeed) * 4);

  @override
  State<SwipeAdjust> createState() => _SwipeAdjustState();
}

class _SwipeAdjustState extends State<SwipeAdjust> with SingleTickerProviderStateMixin {
  static const _glide = 0.1; // 굴러가는 거리 = 속도 × 초
  static const _flingFrom = 300.0; // px/s
  static const _maxRoll = 18;

  late final AnimationController _roll;

  var _carry = 0.0; // 한 칸이 안 된 남은 거리
  Duration? _lastTime;

  var _rollFrom = 0, _rollSteps = 0, _rolled = 0;

  @override
  void initState() {
    super.initState();
    _roll = AnimationController(vsync: this)..addListener(_onRoll);
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  int _norm(int v) {
    final w = widget.wrap;
    return w == null ? v : ((v % w) + w) % w;
  }

  void _move(int steps) {
    if (steps != 0) widget.onChanged(_norm(widget.value + steps * widget.step));
  }

  void _onStart(DragStartDetails d) {
    _roll.stop();
    _carry = 0;
    _lastTime = d.sourceTimeStamp;
  }

  void _onUpdate(DragUpdateDetails d) {
    final t = d.sourceTimeStamp;
    final dt = (t != null && _lastTime != null) ? (t - _lastTime!).inMicroseconds / 1000 : 0.0;
    _lastTime = t;
    final speed = dt > 0 ? d.delta.dx.abs() / dt : 0.0;
    _carry += -d.delta.dx / widget.stepWidth * SwipeAdjust.gainFor(speed);
    final whole = _carry.truncate();
    _carry -= whole;
    _move(whole);
  }

  void _onEnd(DragEndDetails d) {
    _lastTime = null;
    _carry = 0;
    final v = d.velocity.pixelsPerSecond.dx;
    if (v.abs() < _flingFrom) return;
    final steps = (-v * _glide / widget.stepWidth * SwipeAdjust.gainFor(v.abs() / 1000)).round().clamp(-_maxRoll, _maxRoll);
    if (steps == 0) return;
    _rollFrom = widget.value;
    _rollSteps = steps;
    _rolled = 0;
    _roll.duration = Duration(milliseconds: (300 + steps.abs() * 25).clamp(300, 1100));
    _roll.forward(from: 0);
  }

  void _onRoll() {
    final now = (Curves.easeOutCubic.transform(_roll.value) * _rollSteps).round();
    if (now == _rolled) return;
    _rolled = now;
    widget.onChanged(_norm(_rollFrom + now * widget.step));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: widget.child,
    );
  }
}
