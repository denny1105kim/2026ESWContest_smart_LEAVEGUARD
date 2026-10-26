import 'package:flutter/material.dart';

import '../../app/backend.dart';
import '../../device/voice_memo.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/design_canvas.dart';
import '../../shared/widgets/on_screen_keyboard.dart';
import '../../shared/time_text.dart';

/// 녹음 → 받아쓰기 → 다듬기. 저장한 줄들을 돌려주고, 닫으면 null
Future<List<String>?> showVoiceMemo(BuildContext context) {
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xFF101322).withValues(alpha: 0.6),
    builder: (context) => const DesignCanvas.legacy(child: Center(child: _VoiceMemo())),
  );
}

enum _Step { listen, transcribe, refine, done, failed }

class _VoiceMemo extends StatefulWidget {
  const _VoiceMemo();

  @override
  State<_VoiceMemo> createState() => _VoiceMemoState();
}

class _VoiceMemoState extends State<_VoiceMemo> {
  var _step = _Step.listen;
  var _level = 0.0;
  var _elapsed = Duration.zero;
  String? _said;
  List<String>? _memo;
  var _run = 0;

  @override
  void initState() {
    super.initState();
    voiceMemo.warmUp().ignore();
    _start();
  }

  @override
  void dispose() {
    voiceMemo.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final run = ++_run;
    setState(() {
      _step = _Step.listen;
      _level = 0;
      _elapsed = Duration.zero;
      _said = null;
      _memo = null;
    });
    final wav = await voiceMemo.record(
      onLevel: (l) {
        if (mounted && run == _run) setState(() => _level = l);
      },
      onTick: (t) {
        if (mounted && run == _run) setState(() => _elapsed = t);
      },
    );
    if (!mounted || run != _run) return;
    if (wav == null) return setState(() => _step = _Step.failed);
    setState(() => _step = _Step.transcribe);
    final said = await voiceMemo.transcribe(wav);
    if (!mounted || run != _run) return;
    if (said == null) return setState(() => _step = _Step.failed);
    setState(() {
      _said = said;
      _step = _Step.refine;
    });
    final memo = await voiceMemo.refine(said);
    if (!mounted || run != _run) return;
    setState(() {
      _memo = memo;
      _step = _Step.done;
    });
  }

  Future<void> _keyboard() async {
    _run++;
    voiceMemo.cancel();
    final name = await showTextEntry(context, title: '내일 메모', initial: _memo?.join(' · ') ?? '', hint: '예: 보조배터리 챙기기', confirmLabel: '저장');
    if (!mounted) return;
    Navigator.pop(context, name == null ? null : [name]);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.dialog,
      borderRadius: BorderRadius.circular(Radii.card),
      child: SizedBox(
        width: 600,
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('내일 메모', style: Txt.sub)),
                  RoundIconButton(Icons.close_rounded, size: 44, background: Palette.raised, onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: Space.m),
              SizedBox(height: 190, child: Center(child: _body())),
              const SizedBox(height: Space.l),
              _buttons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (_step) {
        _Step.listen => Column(mainAxisSize: MainAxisSize.min, children: [
            _Mic(level: _level),
            const SizedBox(height: Space.m),
            const Text('말씀하세요', style: Txt.title),
            const SizedBox(height: Space.m),
            _Timer(elapsed: _elapsed),
          ]),
        _Step.transcribe || _Step.refine => Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
            const SizedBox(height: Space.m),
            Text(_said ?? '받아쓰는 중', style: Txt.body.copyWith(color: Palette.muted), maxLines: 2, textAlign: TextAlign.center),
          ]),
        _Step.done => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final l in _memo ?? const <String>[])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 14), decoration: const BoxDecoration(color: Color(0xFFFFC857), shape: BoxShape.circle)),
                  Expanded(child: Text(l, style: Txt.title.copyWith(fontSize: 26), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            const SizedBox(height: Space.s),
            Text('“${_said ?? ''}”', style: Txt.sub.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          ]),
        _Step.failed => const Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.mic_off_rounded, size: 44, color: Palette.faint),
            SizedBox(height: Space.m),
            Text('잘 못 들었어요', style: Txt.title),
          ]),
      };

  Widget _buttons() {
    final row = switch (_step) {
      _Step.listen => [Expanded(child: AppButton('그만', expand: true, onPressed: voiceMemo.stopRecording))],
      _Step.transcribe || _Step.refine => [Expanded(child: AppButton.ghost('키보드로', expand: true, onPressed: _keyboard))],
      _Step.done => [
          Expanded(child: AppButton.ghost('다시', expand: true, onPressed: _start)),
          const SizedBox(width: Space.s),
          Expanded(child: AppButton.ghost('고치기', expand: true, onPressed: _keyboard)),
          const SizedBox(width: Space.s),
          Expanded(child: AppButton('저장', expand: true, onPressed: () => Navigator.pop(context, _memo))),
        ],
      _Step.failed => [
          Expanded(child: AppButton.ghost('키보드로', expand: true, onPressed: _keyboard)),
          const SizedBox(width: Space.s),
          Expanded(child: AppButton('다시', expand: true, onPressed: _start)),
        ],
    };
    return Row(children: row);
  }
}

class _Timer extends StatelessWidget {
  const _Timer({required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final max = VoiceMemo.maxRecord;
    return Column(children: [
      SizedBox(
        width: 260,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: (elapsed.inMilliseconds / max.inMilliseconds).clamp(0.0, 1.0), minHeight: 5, color: Colors.white, backgroundColor: Palette.raised),
        ),
      ),
      const SizedBox(height: 6),
      Text('${mmss(elapsed)} / ${mmss(max)}', style: Txt.sub.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
    ]);
  }
}

class _Mic extends StatelessWidget {
  const _Mic({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 64 + 32 * level,
            height: 64 + 32 * level,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Palette.accent.withValues(alpha: 0.25 + 0.3 * level)),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: const Icon(Icons.mic_rounded, size: 34, color: Palette.ink),
          ),
        ],
      ),
    );
  }
}
