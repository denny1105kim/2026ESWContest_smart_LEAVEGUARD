import 'package:flutter/material.dart';

import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/design_canvas.dart';
import '../../../shared/widgets/on_screen_keyboard.dart';
import '../../../core/theme/tokens.dart';
import '../../../device/connman.dart';
import '../settings_screen.dart';

/// 비밀번호는 ConnMan 에 넘긴 뒤 버린다
class WifiJoinInput {
  final String? name; // 이름 숨긴 네트워크만
  final String passphrase;
  final bool open; // 이름 숨긴 네트워크의 보안 없음
  final Ipv4? ip; // null 이면 자동
  final List<String> dns;

  const WifiJoinInput({this.name, this.passphrase = '', this.open = false, this.ip, this.dns = const []});
}

/// [network] 가 null 이면 숨은 네트워크 직접 추가. [last] 는 비밀번호가 틀렸을 때 다시 채울 값
Future<WifiJoinInput?> showWifiJoin(BuildContext context, {WifiNetwork? network, WifiJoinInput? last, bool wrongKey = false}) {
  return _fullScreen(context, _WifiJoin(network: network, last: last, wrongKey: wrongKey));
}

/// 결과 ip.method 가 dhcp 면 자동으로 되돌린 것
Future<(Ipv4, List<String>)?> showStaticIp(BuildContext context, {required String network, Ipv4? initial, List<String> dns = const []}) {
  return _fullScreen(context, _StaticIp(network: network, initial: initial, dns: dns));
}

Future<T?> _fullScreen<T>(BuildContext context, Widget child) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => ColoredBox(color: Palette.bg, child: DesignCanvas.legacy(child: WallpadBackground(child: Material(color: Colors.transparent, child: child)))),
    transitionBuilder: (context, anim, _, child) => SlideTransition(
      position: anim.drive(CurveTween(curve: Curves.easeOutCubic)).drive(Tween(begin: const Offset(0, 0.08), end: Offset.zero)),
      child: FadeTransition(opacity: anim, child: RepaintBoundary(child: child)),
    ),
  );
}

class _Header extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const _Header({required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, 0),
      child: Row(
        children: [
          RoundIconButton(Icons.close_rounded, onPressed: () => Navigator.pop(context)),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Txt.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle case final s?) Text(s, style: Txt.sub, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class WifiChoice extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;

  const WifiChoice({super.key, required this.labels, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: Space.s),
            child: Material(
              color: i == selected ? Palette.soft(Palette.accent) : Palette.surface,
              shape: StadiumBorder(side: i == selected ? BorderSide.none : const BorderSide(color: Palette.line, width: 1.5)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onTap(i),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  child: Text(labels[i],
                      style: TextStyle(fontSize: 17, fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500, color: i == selected ? Palette.accent : Palette.muted)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _Field { name, pass }

class _WifiJoin extends StatefulWidget {
  final WifiNetwork? network;
  final WifiJoinInput? last;
  final bool wrongKey;

  const _WifiJoin({this.network, this.last, this.wrongKey = false});

  @override
  State<_WifiJoin> createState() => _WifiJoinState();
}

class _WifiJoinState extends State<_WifiJoin> {
  late String _name = widget.last?.name ?? '';
  late String _pass = widget.last?.passphrase ?? '';
  late bool _open = widget.last?.open ?? false;
  late Ipv4? _ip = widget.last?.ip;
  late List<String> _dns = widget.last?.dns ?? const [];
  late _Field _focus = _hidden ? _Field.name : _Field.pass;
  late bool _wrong = widget.wrongKey;
  var _show = false;

  bool get _hidden => widget.network == null;

  // WPA 비밀번호는 8~63자
  bool get _passOk => _open || (_pass.length >= 8 && _pass.length <= 63);
  bool get _canJoin => _passOk && (!_hidden || _name.trim().isNotEmpty);

  void _type(String ch) => setState(() {
        _wrong = false;
        if (_focus == _Field.name) {
          if (_name.length < 32) _name += ch;
        } else if (_pass.length < 63) {
          _pass += ch;
        }
      });

  void _back() => setState(() {
        _wrong = false;
        if (_focus == _Field.name) {
          if (_name.isNotEmpty) _name = _name.substring(0, _name.length - 1);
        } else if (_pass.isNotEmpty) {
          _pass = _pass.substring(0, _pass.length - 1);
        }
      });

  Future<void> _pickIp(int i) async {
    if (i == 0) {
      setState(() => _ip = null);
      return;
    }
    final r = await showStaticIp(context, network: widget.network?.name ?? _name, initial: _ip, dns: _dns);
    if (r == null || !mounted) return;
    setState(() {
      _ip = r.$1.method == 'manual' ? r.$1 : null;
      _dns = r.$2;
    });
  }

  void _done() => Navigator.pop(
        context,
        WifiJoinInput(name: _hidden ? _name.trim() : null, passphrase: _open ? '' : _pass, open: _open, ip: _ip, dns: _dns),
      );

  @override
  Widget build(BuildContext context) {
    final n = widget.network;
    final masked = _show ? _pass : '•' * _pass.length;
    final show = Padding(
      padding: const EdgeInsets.only(left: Space.s),
      child: Material(
        color: Palette.raised,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() => _show = !_show),
          child: SizedBox(width: 76, height: 44, child: Center(child: Text(_show ? '숨기기' : '보기', style: Txt.caption.copyWith(color: Palette.muted, fontWeight: FontWeight.w700, fontSize: 17)))),
        ),
      ),
    );
    return Column(
      children: [
        _Header(
          title: _hidden ? '네트워크 직접 추가' : '${n?.name} 비밀번호',
          subtitle: _hidden ? null : '${n!.securityLabel} · 신호 ${n.signal}',
        ),
        Expanded(
          child: Center(
            child: SizedBox(
              width: 640,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_hidden) ...[
                    _focus == _Field.name
                        ? TextDisplay(text: _name, hint: '네트워크 이름', fontSize: 24)
                        : FieldBox(value: _name, hint: '네트워크 이름', onTap: () => setState(() => _focus = _Field.name)),
                    const SizedBox(height: Space.s),
                    if (!_open)
                      _focus == _Field.pass
                          ? TextDisplay(text: masked, hint: '비밀번호', fontSize: 24, trailing: show)
                          : FieldBox(value: masked, hint: '비밀번호', onTap: () => setState(() => _focus = _Field.pass)),
                  ] else
                    TextDisplay(text: masked, hint: '비밀번호', error: _wrong, trailing: show),
                  const SizedBox(height: Space.s),
                  if (_wrong)
                    const Padding(
                      padding: EdgeInsets.only(bottom: Space.s),
                      child: Row(
                        children: [
                          Icon(Icons.error_rounded, color: Palette.pending, size: 20),
                          SizedBox(width: 6),
                          Text('비밀번호가 맞지 않아요 · 다시 확인해 주세요', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.pending)),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      if (_hidden) ...[
                        const Text('보안', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.muted)),
                        const SizedBox(width: Space.m),
                        WifiChoice(
                          labels: const ['WPA2 / WPA3', '없음'],
                          selected: _open ? 1 : 0,
                          onTap: (i) => setState(() {
                            _open = i == 1;
                            _focus = _open ? _Field.name : _focus;
                          }),
                        ),
                        const SizedBox(width: Space.l),
                      ],
                      const Text('IP', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.muted)),
                      const SizedBox(width: Space.m),
                      WifiChoice(labels: const ['자동', '고정 IP'], selected: _ip == null ? 0 : 1, onTap: _pickIp),
                      const Spacer(),
                      Text(
                        _ip != null ? _ip!.address : (_open || _pass.isEmpty || _passOk ? '' : '8자 이상'),
                        style: Txt.caption.copyWith(fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        RepaintBoundary(
          child: AsciiKeyboard(onKey: _type, onBackspace: _back, doneLabel: '연결', onDone: _canJoin ? _done : null),
        ),
      ],
    );
  }
}

class _StaticIp extends StatefulWidget {
  final String network;
  final Ipv4? initial;
  final List<String> dns;

  const _StaticIp({required this.network, this.initial, this.dns = const []});

  @override
  State<_StaticIp> createState() => _StaticIpState();
}

class _StaticIpState extends State<_StaticIp> {
  static const _labels = ['IP 주소', '서브넷 마스크', '게이트웨이', 'DNS', 'DNS 2 (선택)'];

  late final List<String> _v = [
    widget.initial?.address ?? '',
    widget.initial?.netmask ?? '255.255.255.0',
    widget.initial?.gateway ?? '',
    widget.dns.isNotEmpty ? widget.dns[0] : '',
    widget.dns.length > 1 ? widget.dns[1] : '',
  ];
  var _focus = 0;

  static bool _isIp(String s) {
    final parts = s.split('.');
    return parts.length == 4 && parts.every((p) => p.isNotEmpty && p.length <= 3 && (int.tryParse(p) ?? 256) <= 255);
  }

  bool _ok(int i) => i == 4 ? _v[4].isEmpty || _isIp(_v[4]) : _isIp(_v[i]);
  bool get _allOk => [for (var i = 0; i < 5; i++) _ok(i)].every((x) => x);

  void _key(String k) => setState(() {
        if (k == '<') {
          if (_v[_focus].isNotEmpty) _v[_focus] = _v[_focus].substring(0, _v[_focus].length - 1);
        } else if (_v[_focus].length < 15) {
          _v[_focus] += k;
        }
      });

  void _save() => Navigator.pop(context, (
        Ipv4(method: 'manual', address: _v[0], netmask: _v[1], gateway: _v[2]),
        [_v[3], if (_v[4].isNotEmpty) _v[4]],
      ));

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Header(
          title: '고정 IP 설정',
          subtitle: widget.network,
          action: AppButton.ghost('자동으로 받기', onPressed: () => Navigator.pop(context, (Ipv4.dhcp, const <String>[]))),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, Space.xl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(Space.l),
                    decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.card),
                    child: Column(
                      children: [
                        for (var i = 0; i < 5; i++) ...[
                          if (i > 0) const SizedBox(height: Space.s),
                          _IpRow(
                            label: _labels[i],
                            value: _v[i],
                            focused: _focus == i,
                            bad: _v[i].isNotEmpty && !_ok(i),
                            onTap: () => setState(() => _focus = i),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Space.l),
                SizedBox(
                  width: 360,
                  child: Container(
                    padding: const EdgeInsets.all(Space.m),
                    decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card)),
                    child: Column(
                      children: [
                        for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['.', '0', '<']]) ...[
                          SizedBox(
                            height: 58,
                            child: Row(
                              children: [
                                for (final k in row)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: Material(
                                        color: k == '<' ? const Color(0x3DFFFFFF) : const Color(0x29FFFFFF),
                                        borderRadius: BorderRadius.circular(12),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: () => _key(k),
                                          child: Center(
                                            child: k == '<'
                                                ? const Icon(Icons.backspace_outlined, color: Palette.text)
                                                : Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: Palette.text)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const Spacer(),
                        AppButton.ghost('다음 칸', expand: true, onPressed: () => setState(() => _focus = (_focus + 1) % 5)),
                        const SizedBox(height: Space.s),
                        AppButton('저장', expand: true, onPressed: _allOk ? _save : null),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IpRow extends StatelessWidget {
  final String label;
  final String value;
  final bool focused;
  final bool bad;
  final VoidCallback onTap;

  const _IpRow({required this.label, required this.value, required this.focused, required this.bad, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final border = bad ? Palette.pending : (focused ? Palette.accent : Palette.line);
    return SizedBox(
      height: 60,
      child: Material(
        color: Palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button), side: BorderSide(color: border, width: focused || bad ? 2 : 1.5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l + 4),
            child: Row(
              children: [
                SizedBox(width: 140, child: Text(label, style: Txt.sub.copyWith(fontWeight: FontWeight.w500))),
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Palette.text)),
                if (focused) Container(width: 3, height: 28, margin: const EdgeInsets.only(left: 2), color: Palette.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
