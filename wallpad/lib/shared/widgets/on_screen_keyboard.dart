import 'dart:async';

import 'package:flutter/material.dart';

import '../hangul.dart';
import 'design_canvas.dart';
import '../../core/config/constants.dart';
import '../../core/theme/tokens.dart';
import 'buttons.dart';

/// 두벌식 화면 키보드 (조합은 [HangulComposer]).
class OnScreenKeyboard extends StatefulWidget {
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback? onDone; // null 이면 완료 키 비활성
  final String doneLabel;

  const OnScreenKeyboard({super.key, required this.onKey, required this.onBackspace, this.onDone, this.doneLabel = '완료'});

  static const sheetColor = Palette.surface;

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  var _shift = false;

  static const _row1 = ['ㅂ', 'ㅈ', 'ㄷ', 'ㄱ', 'ㅅ', 'ㅛ', 'ㅕ', 'ㅑ', 'ㅐ', 'ㅔ'];
  static const _row1Shift = ['ㅃ', 'ㅉ', 'ㄸ', 'ㄲ', 'ㅆ', 'ㅛ', 'ㅕ', 'ㅑ', 'ㅒ', 'ㅖ'];
  static const _row2 = ['ㅁ', 'ㄴ', 'ㅇ', 'ㄹ', 'ㅎ', 'ㅗ', 'ㅓ', 'ㅏ', 'ㅣ'];
  static const _row3 = ['ㅋ', 'ㅌ', 'ㅊ', 'ㅍ', 'ㅠ', 'ㅜ', 'ㅡ'];

  void _type(String ch) {
    widget.onKey(ch);
    if (_shift) setState(() => _shift = false); // 쌍자음은 한 번만
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: OnScreenKeyboard.sheetColor, borderRadius: BorderRadius.circular(Radii.card)),
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row([for (final k in _shift ? _row1Shift : _row1) _Key(k, onTap: () => _type(k))]),
          _gap,
          _row([
            const Spacer(),
            for (final k in _row2) _Key(k, onTap: () => _type(k)),
            const Spacer(),
          ]),
          _gap,
          _row([
            _Key('', flex: 3, icon: _shift ? Icons.keyboard_capslock_rounded : Icons.arrow_upward_rounded, dark: true,
                highlight: _shift, onTap: () => setState(() => _shift = !_shift)),
            for (final k in _row3) _Key(k, onTap: () => _type(k)),
            _Key('', flex: 3, icon: Icons.backspace_outlined, dark: true, onTap: widget.onBackspace),
          ]),
          _gap,
          _row([
            _Key('띄어쓰기', flex: 14, small: true, onTap: () => _type(' ')),
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AppButton(widget.doneLabel, height: 50, expand: true, onPressed: widget.onDone),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  static const _gap = SizedBox(height: 6);

  Widget _row(List<Widget> keys) => SizedBox(height: 50, child: Row(children: keys));
}

class _Key extends StatelessWidget {
  final String label;
  final IconData? icon;
  final int flex;
  final bool dark, highlight, small;
  final VoidCallback onTap;

  const _Key(this.label, {required this.onTap, this.icon, this.flex = 2, this.dark = false, this.highlight = false, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: highlight ? Colors.white : (dark ? const Color(0x3DFFFFFF) : const Color(0x29FFFFFF)),
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 24, color: highlight ? Palette.ink : Palette.text)
                  : Text(label, style: TextStyle(fontSize: small ? 17 : 23, fontWeight: highlight ? FontWeight.w700 : FontWeight.w500, color: highlight ? Palette.ink : Palette.text)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 영문·숫자·기호 키보드.
class AsciiKeyboard extends StatefulWidget {
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback? onDone; // null 이면 완료 키 비활성
  final String doneLabel;

  const AsciiKeyboard({super.key, required this.onKey, required this.onBackspace, this.onDone, this.doneLabel = '완료'});

  @override
  State<AsciiKeyboard> createState() => _AsciiKeyboardState();
}

class _AsciiKeyboardState extends State<AsciiKeyboard> {
  var _shift = false;
  var _symbols = false;

  static const _letters = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  static const _signs = ['!@#\$%^&*()', "-_=+[]{};:", "'\",./?\\|~"];

  void _type(String ch) {
    widget.onKey(ch);
    if (_shift) setState(() => _shift = false); // 대문자는 한 번만
  }

  List<Widget> _keys(String row) => [
        for (final c in row.split(''))
          if (_shift && !_symbols) _Key(c.toUpperCase(), onTap: () => _type(c.toUpperCase())) else _Key(c, onTap: () => _type(c)),
      ];

  @override
  Widget build(BuildContext context) {
    final rows = _symbols ? _signs : _letters;
    return Container(
      decoration: BoxDecoration(color: OnScreenKeyboard.sheetColor, borderRadius: BorderRadius.circular(Radii.card)),
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(_keys('1234567890')),
          _gap,
          _row(_keys(rows[0])),
          _gap,
          _row([
            if (!_symbols) const Spacer(),
            ..._keys(rows[1]),
            if (!_symbols) const Spacer(),
          ]),
          _gap,
          _row([
            if (!_symbols)
              _Key('', flex: 3, icon: _shift ? Icons.keyboard_capslock_rounded : Icons.arrow_upward_rounded, dark: true,
                  highlight: _shift, onTap: () => setState(() => _shift = !_shift)),
            ..._keys(rows[2]),
            _Key('', flex: _symbols ? 2 : 3, icon: Icons.backspace_outlined, dark: true, onTap: widget.onBackspace),
          ]),
          _gap,
          _row([
            _Key(_symbols ? 'abc' : '!#1', flex: 3, dark: true, small: true, onTap: () => setState(() => _symbols = !_symbols)),
            _Key('띄어쓰기', flex: 11, small: true, onTap: () => _type(' ')),
            _Key('.', onTap: () => _type('.')),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AppButton(widget.doneLabel, height: 50, expand: true, onPressed: widget.onDone),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  static const _gap = SizedBox(height: 6);

  Widget _row(List<Widget> keys) => SizedBox(height: 50, child: Row(children: keys));
}

/// 전체 화면 한글 입력창.
Future<String?> showTextEntry(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirmLabel = '완료',
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => DesignCanvas.fitWidth(width: screenW, child: _TextEntry(title: title, initial: initial, hint: hint, confirmLabel: confirmLabel)),
    // Pi 에서 매 프레임 다시 그리지 않게 RepaintBoundary 로 묶는다
    transitionBuilder: (context, anim, _, child) => SlideTransition(
      position: anim.drive(CurveTween(curve: Curves.easeOutCubic)).drive(Tween(begin: const Offset(0, 0.08), end: Offset.zero)),
      child: FadeTransition(opacity: anim, child: RepaintBoundary(child: child)),
    ),
  );
}

class _TextEntry extends StatefulWidget {
  final String title, initial, hint, confirmLabel;

  const _TextEntry({required this.title, required this.initial, required this.hint, required this.confirmLabel});

  @override
  State<_TextEntry> createState() => _TextEntryState();
}

class _TextEntryState extends State<_TextEntry> {
  final _composer = HangulComposer();

  @override
  void initState() {
    super.initState();
    for (final ch in widget.initial.characters) {
      _composer.type(ch);
    }
  }

  String get _text => _composer.text;

  @override
  Widget build(BuildContext context) {
    final canSave = _text.trim().isNotEmpty;
    return WallpadBackground(
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, 0),
              child: Row(
                children: [
                  RoundIconButton(Icons.close_rounded, onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: Space.l),
                  Text(widget.title, style: Txt.title),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 640,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextDisplay(text: _text, hint: widget.hint, onClear: canSave ? () => setState(() {
                        while (_composer.text.isNotEmpty) {
                          _composer.backspace();
                        }
                      }) : null),
                    ],
                  ),
                ),
              ),
            ),
            // 화면 맨 아래 터치는 OS 가 스와이프로 보고 앱을 닫아서 띄워 둔다
            RepaintBoundary(
              child: Container(
                color: OnScreenKeyboard.sheetColor,
                padding: const EdgeInsets.only(bottom: legacyBottomGap),
                child: OnScreenKeyboard(
                  onKey: (ch) => setState(() => _composer.type(ch)),
                  onBackspace: () => setState(_composer.backspace),
                  doneLabel: widget.confirmLabel,
                  onDone: canSave ? () => Navigator.pop(context, _text.trim()) : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 커서가 깜빡이는 입력칸 모양. 입력은 화면 키보드로 받는다.
class TextDisplay extends StatefulWidget {
  final String text;
  final String hint;
  final VoidCallback? onClear;
  final double fontSize;
  final Widget? trailing;
  final bool error;

  const TextDisplay({super.key, required this.text, this.hint = '', this.onClear, this.fontSize = 34, this.trailing, this.error = false});

  @override
  State<TextDisplay> createState() => _TextDisplayState();
}

class _TextDisplayState extends State<TextDisplay> {
  // 애니메이션 커서는 계속 다시 그려 키 입력이 버벅여서 타이머로 켜고 끈다
  var _cursorOn = true;
  late final Timer _blink;

  @override
  void initState() {
    super.initState();
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) => setState(() => _cursorOn = !_cursorOn));
  }

  @override
  void didUpdateWidget(TextDisplay old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _cursorOn = true;
  }

  @override
  void dispose() {
    _blink.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final empty = widget.text.isEmpty;
    return RepaintBoundary(
      child: Container(
        height: widget.fontSize * 2.4,
        padding: const EdgeInsets.only(left: Space.xl, right: Space.s),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: widget.error ? Palette.pending : Palette.line, width: 2),
          boxShadow: Shadows.card,
        ),
        child: Row(
          children: [
            if (!empty) Text(widget.text, style: TextStyle(fontSize: widget.fontSize, fontWeight: FontWeight.w600, color: Palette.text)),
            Container(width: 3, height: widget.fontSize * 1.1, margin: const EdgeInsets.only(left: 2), color: _cursorOn ? (widget.error ? Palette.pending : Palette.accent) : Colors.transparent),
            if (empty)
              Padding(
                padding: const EdgeInsets.only(left: Space.s),
                child: Text(widget.hint, style: TextStyle(fontSize: widget.fontSize, color: Palette.faint)),
              ),
            const Spacer(),
            if (widget.onClear != null) RoundIconButton(Icons.close_rounded, size: 44, onPressed: widget.onClear, color: Palette.muted),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ),
    );
  }
}
