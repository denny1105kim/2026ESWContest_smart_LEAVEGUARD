import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/models.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/on_screen_keyboard.dart';
import '../../shared/widgets/design_canvas.dart';
import '../../core/data/models.dart';
import '../../app/app_state.dart';
import '../../core/theme/tokens.dart';
import '../../shared/time_text.dart';

/// 소지품 확인 질문. 답이 없으면 잠시 뒤 "나중에" 로 접힌다.
class BelongingQuestionOverlay extends StatefulWidget {
  final BelongingQuestion question;

  const BelongingQuestionOverlay({super.key, required this.question});

  @override
  State<BelongingQuestionOverlay> createState() => _BelongingQuestionOverlayState();
}

class _BelongingQuestionOverlayState extends State<BelongingQuestionOverlay> {
  static const _timeout = Duration(seconds: 20);
  Timer? _timer;
  var _saidNo = false;
  Belonging? _other;
  String? _note;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_timeout, () => app.answerQuestion(null));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _no() {
    setState(() => _saidNo = true);
    _rearm();
  }

  void _rearm() {
    _timer?.cancel();
    _timer = Timer(_timeout, () => app.answerQuestion(false));
  }

  void _pickOther(Belonging b) {
    setState(() {
      _other = b;
      _note = null;
    });
    _rearm();
  }

  Future<void> _typeName() async {
    _timer?.cancel();
    final v = await showTextEntry(context, title: '어떤 물건인가요?', hint: '예: 지갑', confirmLabel: '확인');
    if (!mounted) return;
    _rearm();
    final n = v?.trim() ?? '';
    if (n.isEmpty) return;
    final same = app.myBelongings.where((b) => b.name.trim() == n).firstOrNull ?? app.belongings.where((b) => b.name.trim() == n).firstOrNull;
    if (same == null) return setState(() => _note = '‘$n’ 은 등록된 물건이 아니에요. 새로 등록해 주세요');
    if (same.id == '${widget.question.belongingId}') {
      _timer?.cancel();
      app.answerQuestion(true);
      return;
    }
    _pickOther(same);
  }

  String _seenLabel(DateTime t) {
    final ago = DateTime.now().difference(t);
    if (ago < const Duration(minutes: 5)) return '지금 트레이';
    final today = DateTime.now().day == t.day;
    return '${today ? '오늘' : '어제'} ${hhmm(t)} 트레이 사진';
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final item = app.belongingById('${q.belongingId}');
    final name = item?.name ?? '소지품';
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xFF101322).withValues(alpha: 0.55),
        child: DesignCanvas.legacy(
          child: Center(
            child: Material(
              color: Palette.dialog,
              borderRadius: BorderRadius.circular(Radii.card),
              child: SizedBox(
                width: 560,
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: _other != null
                      ? _confirmOther(q, _other!)
                      : _saidNo
                          ? _afterNo(name)
                          : _ask(q, name, item?.thumbnail),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ask(BelongingQuestion q, String name, Uint8List? thumbnail) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('트레이 소지품 확인', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.warn)),
        const SizedBox(height: Space.xs),
        Text('‘$name’ 맞나요?', style: Txt.title.copyWith(fontSize: 26)),
        const SizedBox(height: Space.l),
        Row(
          children: [
            Expanded(child: _photo(q.crop, _seenLabel(q.seenAt))),
            const SizedBox(width: Space.m),
            Expanded(child: _photo(thumbnail, '등록한 사진')),
          ],
        ),
        const SizedBox(height: Space.l),
        Row(
          children: [
            Expanded(child: AppButton.ghost('아니에요', expand: true, onPressed: _no)),
            const SizedBox(width: Space.m),
            Expanded(child: AppButton('맞아요', expand: true, onPressed: () => app.answerQuestion(true))),
          ],
        ),
        const SizedBox(height: Space.s),
        Center(
          child: TextButton(
            onPressed: () => app.answerQuestion(null),
            child: const Text('나중에', style: TextStyle(fontSize: 17, color: Palette.muted)),
          ),
        ),
      ],
    );
  }

  Widget _afterNo(String name) {
    final others = [for (final b in app.myBelongings) if (b.id != '${widget.question.belongingId}') b];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('그럼 어떤 물건인가요?', style: Txt.title.copyWith(fontSize: 24)),
        const SizedBox(height: Space.xs),
        const Text('다른 물건의 뒷면이나 옆면이면 골라 주세요. 다음부터 이렇게 놓여도 알아봐요', style: Txt.caption),
        const SizedBox(height: Space.l),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final b in others) _chip(b.name, () => _pickOther(b)),
            _chip('이름 입력', _typeName, icon: Icons.keyboard_rounded),
          ],
        ),
        if (_note != null) ...[
          const SizedBox(height: Space.m),
          Text(_note!, style: Txt.caption.copyWith(color: Palette.warn)),
        ],
        const SizedBox(height: Space.xl),
        Row(
          children: [
            Expanded(child: AppButton.ghost('그냥 두기', expand: true, onPressed: () => app.answerQuestion(false))),
            const SizedBox(width: Space.m),
            Expanded(
              child: AppButton('새로 등록', expand: true, onPressed: () async {
                await app.answerQuestion(false);
                app.openTrayPeek();
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _confirmOther(BelongingQuestion q, Belonging b) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('트레이 소지품 확인', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.warn)),
        const SizedBox(height: Space.xs),
        Text('‘${b.name}’ 맞나요?', style: Txt.title.copyWith(fontSize: 26)),
        const SizedBox(height: Space.l),
        Row(
          children: [
            Expanded(child: _photo(q.crop, _seenLabel(q.seenAt))),
            const SizedBox(width: Space.m),
            Expanded(child: _photo(b.thumbnail, '‘${b.name}’ 등록한 사진')),
          ],
        ),
        const SizedBox(height: Space.l),
        Row(
          children: [
            Expanded(
              child: AppButton.ghost('아니에요', expand: true, onPressed: () {
                setState(() => _other = null);
                _rearm();
              }),
            ),
            const SizedBox(width: Space.m),
            Expanded(child: AppButton('맞아요', expand: true, onPressed: () => app.answerQuestionAs(b.id))),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, VoidCallback onTap, {IconData? icon}) {
    return Material(
      color: Palette.raised,
      borderRadius: BorderRadius.circular(Radii.button),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20, color: Palette.muted), const SizedBox(width: 6)],
            Text(label, style: Txt.bodyStrong),
          ]),
        ),
      ),
    );
  }

  Widget _photo(Uint8List? bytes, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.button),
          child: Container(
            height: 170,
            width: double.infinity,
            color: Palette.raised,
            child: bytes == null ? const Icon(Icons.image_not_supported_outlined, color: Palette.faint, size: 40) : Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(label, style: Txt.caption),
      ],
    );
  }
}
