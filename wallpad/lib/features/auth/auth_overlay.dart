import 'dart:async';

import 'package:flutter/material.dart';

import 'pin.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/pin_pad.dart';
import '../../app/app_state.dart';
import '../../core/theme/tokens.dart';

/// PIN 본인 확인 창. 통과하면 AppState 가 요청한 일을 이어서 한다
class AuthOverlay extends StatefulWidget {
  const AuthOverlay({super.key, required this.request});

  final AuthRequest request;

  @override
  State<AuthOverlay> createState() => _AuthOverlayState();
}

enum _Mode { pin, create, confirm, noPin }

class _AuthOverlayState extends State<AuthOverlay> {
  late _Mode _mode;
  var _digits = '';

  String? _first;
  String? _message;
  var _messageIsError = false;

  Timer? _tick;

  String get _id => widget.request.userId;
  bool get _hasPin => app.hasPin(_id);

  @override
  void initState() {
    super.initState();
    _mode = switch (widget.request.purpose) {
      AuthPurpose.create => _Mode.create,
      AuthPurpose.pick || AuthPurpose.switchTo || AuthPurpose.delete => _hasPin ? _Mode.pin : _Mode.noPin,
    };
    // 잠금 남은 시간 표시
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lockLeft != null || _mode == _Mode.pin) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _say(String? s, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = s;
      _messageIsError = error;
    });
  }

  Duration? get _lockLeft => _mode == _Mode.pin ? app.pinLockOf(_id).remaining(DateTime.now()) : null;

  void _press(String d) {
    if (_lockLeft != null || _digits.length >= Pin.length) return;
    setState(() => _digits += d);
    if (_digits.length == Pin.length) Future.delayed(const Duration(milliseconds: 120), _submit);
  }

  void _back() {
    if (_digits.isNotEmpty) setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _submit() async {
    if (!mounted) return;
    final d = _digits;
    switch (_mode) {
      case _Mode.pin:
        final r = app.submitPin(d);
        if (r == PinResult.ok || !mounted) return;
        final lock = app.pinLockOf(_id);
        setState(() => _digits = '');
        _say(r == PinResult.locked ? null : '틀렸어요 · ${lock.triesLeft}회 남음', error: true);
      case _Mode.create:
        setState(() {
          _first = d;
          _digits = '';
          _mode = _Mode.confirm;
          _message = null;
        });
      case _Mode.confirm:
        if (d == _first) return app.createPin(d);
        setState(() {
          _first = null;
          _digits = '';
          _mode = _Mode.create;
        });
        _say('PIN이 달라요', error: true);
      case _Mode.noPin:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = app.userOf(_id);
    if (user == null) return const SizedBox.shrink();
    final name = user.name;
    final (title, sub) = switch ((widget.request.purpose, _mode)) {
      (_, _Mode.create) => (name, 'PIN 설정'),
      (_, _Mode.confirm) => (name, 'PIN 확인'),
      (_, _Mode.noPin) => (name, 'PIN 없음'),
      (AuthPurpose.delete, _) => (name, '삭제'),
      (_, _) => (name, null),
    };

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 560,
          padding: const EdgeInsets.fromLTRB(Space.xxl, Space.xl, Space.xxl, Space.xl),
          decoration: BoxDecoration(color: Palette.dialog, borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.lifted),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Avatar(user, size: 56),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Txt.title.copyWith(fontSize: 26), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (sub != null) Text(sub, style: Txt.sub, maxLines: 1),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.l),
              switch (_mode) {
                _Mode.noPin => _noPin(),
                _ => _pinPad(),
              },
            ],
          ),
        ),
      ),
    );
  }

  // PIN 은 얼굴 인식으로 들어왔을 때만 정할 수 있다
  Widget _noPin() {
    return Row(
      children: [
        Expanded(child: AppButton.ghost('닫기', onPressed: app.cancelAuth, expand: true)),
        const SizedBox(width: Space.m),
        Expanded(
          child: AppButton(
            '다시 인식',
            icon: Icons.face_rounded,
            expand: true,
            onPressed: () {
              app.cancelAuth();
              app.go(Stage.identifying);
            },
          ),
        ),
      ],
    );
  }

  Widget _pinPad() {
    final left = _lockLeft;
    return PinPad(
      filled: _digits.length,
      onDigit: _press,
      onBack: _back,
      onCancel: app.cancelAuth,
      locked: left != null,
      message: left != null ? '${left.inSeconds + 1}초 후 다시' : _message,
      error: left != null || _messageIsError,
    );
  }
}
