import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../device/camera/camera_session.dart';
import '../../shared/widgets/camera_preview.dart';
import '../../app/backend.dart';
import '../../device/camera/vision.dart';
import 'ob_widgets.dart';

/// 정면 · 오른쪽 · 왼쪽을 고개 각도로 확인해 자동으로 찍는다. 저장은 부르는 쪽이 한다
class FaceStep extends StatefulWidget {
  final ValueChanged<Map<String, List<double>>> onDone;
  final bool saving;

  const FaceStep({super.key, required this.onDone, this.saving = false});

  @override
  State<FaceStep> createState() => _FaceStepState();
}

class _FaceStepState extends State<FaceStep> with CameraSession {
  // 좌우는 거울 미리보기 기준(사용자 기준)
  static const _poses = ['front', 'right', 'left'];
  static const _poseNames = ['정면', '오른쪽', '왼쪽'];

  // yaw + 는 화면 왼쪽. 5점 랜드마크 각도가 작게 나와서 좌우 기준을 낮게 잡았다
  static const _yawRange = {'front': (-10.0, 10.0), 'left': (10.0, 60.0), 'right': (-60.0, -10.0)};
  static const _maxPitch = 20.0;

  static const _hold = Duration(milliseconds: 300);

  // 옆얼굴이라 일반 조회 기준보다 낮게
  static const _samePerson = 0.3;

  static const _preview = Size.square(376);

  final _faces = <String, List<double>>{};
  var _snapping = false;
  DateTime? _inRangeSince;
  String? _hint;
  String? _error;
  Timer? _fake;

  int get _shots => _faces.length;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _fake?.cancel();
    super.dispose();
  }

  void _start() {
    _fake?.cancel();
    setState(() {
      _faces.clear();
      _snapping = false;
      _hint = _error = null;
    });
    if (!onBoard) {
      // 보드가 아니면 촬영을 흉내만 낸다
      _fake = Timer.periodic(const Duration(milliseconds: 1100), (t) {
        if (!mounted) return t.cancel();
        setState(() => _faces[_poses[_shots]] = const []);
        if (_shots == _poses.length) {
          t.cancel();
          widget.onDone(Map.of(_faces));
        }
      });
      return;
    }
    openCamera('preview');
  }

  @override
  void onVision(VisionEvent e) {
    switch (e.type) {
      case 'started':
        session?.track(CameraPreviewBox.visibleArea(_preview));
      case 'pose':
        if (!_snapping && _shots < _poses.length) _onPose(e);
      case 'face':
        if (_snapping) _onSnap(e);
      case 'none' || 'many' || 'outside':
        _inRangeSince = null;
        _snapping = false;
        _showHint(switch (e.type) {
          'many' => '한 사람만 카메라 앞에 서 주세요',
          'outside' => '얼굴을 동그라미 가운데에 맞춰 주세요',
          _ => '얼굴이 보이지 않아요',
        });
    }
  }

  @override
  void cameraFailed() {
    setState(() {
      _snapping = false;
      _error = '카메라를 열지 못했어요';
    });
  }

  void _showHint(String? hint) {
    if (hint != _hint && mounted) setState(() => _hint = hint);
  }

  String? _poseHint(String pose, double yaw, double pitch) {
    final (lo, hi) = _yawRange[pose]!;
    if (pitch > _maxPitch) return '고개를 조금 내려 주세요';
    if (pitch < -_maxPitch) return '고개를 조금 들어 주세요';
    if (yaw < lo) return pose == 'right' ? '너무 많이 돌렸어요, 조금만 돌아와 주세요' : (pose == 'front' ? '정면을 봐 주세요' : '왼쪽으로 조금 더 돌려 주세요');
    if (yaw > hi) return pose == 'left' ? '너무 많이 돌렸어요, 조금만 돌아와 주세요' : (pose == 'front' ? '정면을 봐 주세요' : '오른쪽으로 조금 더 돌려 주세요');
    return null;
  }

  void _onPose(VisionEvent e) {
    final pose = _poses[_shots];
    final off = _poseHint(pose, e.yaw, e.pitch);
    if (off != null || !e.steady) {
      _inRangeSince = null;
      return _showHint(off ?? '잠깐 멈춰 주세요');
    }
    _showHint('좋아요, 그대로 있어 주세요');
    final since = _inRangeSince ??= DateTime.now();
    if (DateTime.now().difference(since) < _hold) return;
    _inRangeSince = null;
    _snapping = true;
    session?.snap(CameraPreviewBox.visibleArea(_preview));
  }

  void _onSnap(VisionEvent e) {
    _snapping = false;
    final pose = _poses[_shots];
    final (lo, hi) = _yawRange[pose]!;
    if (e.yaw < lo - 8 || e.yaw > hi + 8 || e.pitch.abs() > _maxPitch + 8) return _showHint('움직였어요, 다시 맞춰 주세요');
    final embedding = e.embedding;
    final front = _faces['front'];
    if (pose != 'front' && front != null && front.isNotEmpty && _cosine(front, embedding) < _samePerson) {
      return _showHint('정면에서 찍은 분과 같은 분만 등록할 수 있어요');
    }
    setState(() {
      _faces[pose] = embedding;
      _hint = null;
    });
    if (_shots < _poses.length) return;
    closeCamera();
    widget.onDone(Map.of(_faces));
  }

  static double _cosine(List<double> a, List<double> b) {
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return na == 0 || nb == 0 ? 0 : dot / sqrt(na * nb);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final status = widget.saving ? '저장 중' : (error != null ? '다시 찍어 주세요' : '촬영 중');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 520,
          child: Column(
            children: [
              SizedBox.square(
                dimension: 470,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(width: 470, height: 470, decoration: const BoxDecoration(color: Ob.navyConnector, shape: BoxShape.circle)),
                    Container(width: 440, height: 440, decoration: const BoxDecoration(color: Ob.card, shape: BoxShape.circle)),
                    CameraPreviewBox(width: _preview.width, height: _preview.height, circle: true, frame: frame),
                    CustomPaint(size: const Size.square(452), painter: _ShotRing(done: _shots, total: _poses.length)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(status, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: error != null ? Ob.red : Ob.green)),
            ],
          ),
        ),
        const SizedBox(width: 70),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _poses.length; i++) ...[
                  _PoseRow(index: i, name: _poseNames[i], state: i < _shots ? _Pose.done : (i == _shots ? _Pose.now : _Pose.wait)),
                  const SizedBox(height: 22),
                ],
                const SizedBox(height: 8),
                if (error != null)
                  Row(
                    children: [
                      Expanded(child: Text(error, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: Ob.red))),
                      ObButton('다시 찍기', primary: false, width: 200, onTap: _start),
                    ],
                  )
                else
                  Text(_hint ?? '', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600, color: Ob.muted)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _Pose { done, now, wait }

class _PoseRow extends StatelessWidget {
  final int index;
  final String name;
  final _Pose state;

  const _PoseRow({required this.index, required this.name, required this.state});

  @override
  Widget build(BuildContext context) {
    final wait = state == _Pose.wait;
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: BoxDecoration(
        color: wait ? Ob.chip : Ob.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: wait ? Colors.transparent : Ob.accent, width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: switch (state) { _Pose.done => Ob.green, _Pose.now => Ob.accent, _Pose.wait => Ob.navyStep },
            ),
            child: state == _Pose.done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 32)
                : Text('${index + 1}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: wait ? Ob.faint : Colors.white)),
          ),
          const SizedBox(width: 26),
          SizedBox(width: 300, child: Text(name, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Ob.text))),
          Text(switch (state) { _Pose.done => '완료', _Pose.now => '촬영 중', _Pose.wait => '대기' },
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: wait ? Ob.faint : Ob.green)),
        ],
      ),
    );
  }
}

class _ShotRing extends CustomPainter {
  final int done, total;

  _ShotRing({required this.done, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(6);
    const gap = 0.12;
    final seg = 2 * pi / total;
    for (var i = 0; i < total; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = i < done ? Ob.green : Ob.navyConnector;
      canvas.drawArc(rect, -pi / 2 + i * seg + gap / 2, seg - gap, false, paint);
    }
  }

  @override
  bool shouldRepaint(_ShotRing old) => old.done != done;
}
