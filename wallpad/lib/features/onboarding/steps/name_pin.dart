part of '../onboarding_screen.dart';

extension _NamePinSteps on _OnboardingScreenState {
  Widget _pinBody() => LayoutBuilder(
        builder: (context, box) => Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            // 키패드 원래 크기 400x335 를 남은 높이에 맞춰 키운다
            width: (box.maxHeight * 400 / 335).clamp(400.0, 680.0),
            child: FittedBox(
              child: SizedBox(
                width: 400,
                child: PinPad(
                  filled: _pin.length,
                  onDigit: _pressPin,
                  onBack: _backPin,
                  keyColor: Ob.card,
                  keyBorder: Colors.transparent,
                  locked: _saving,
                  message: _saving ? '등록하고 있어요' : _pinMessage,
                  error: _pinMessage != null && !_saving,
                ),
              ),
            ),
          ),
        ),
      );

  Widget _nameBody() {
    final name = _name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 1140,
          height: 100,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: Ob.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: _nameError != null ? Ob.red : Colors.transparent,
                width: 2.5),
          ),
          child: Text(name.isEmpty ? '이름' : _composer.text,
              style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: name.isEmpty ? Ob.faint : Ob.text)),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: _nameError != null
              ? Text(_nameError!,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700, color: Ob.red))
              : name.isEmpty
                  ? null
                  : Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                              color: Ob.green, shape: BoxShape.circle),
                          child: Text(name.characters.first,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                        const SizedBox(width: 18),
                        Text('미리보기  ·  $name님',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: Ob.text)),
                      ],
                    ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.fitWidth,
            child: SizedBox(
              width: 760,
              child: OnScreenKeyboard(
                onKey: (ch) => _setState(() {
                  _composer.type(ch);
                  _nameError = null;
                }),
                onBackspace: () => _setState(() {
                  _composer.backspace();
                  _nameError = null;
                }),
                doneLabel: '다음 →',
                onDone:
                    name.isEmpty || name.characters.length > 8 ? null : _next,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
