import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/card.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/design_canvas.dart';
import '../../../shared/widgets/tags.dart';
import '../../../core/theme/tokens.dart';
import '../../../device/connman.dart';
import '../settings_screen.dart';
import 'wifi_entry.dart';

part 'wifi_rows.dart';

/// 실제 처리는 ConnMan 이 하고 여기선 묻고 보여 주기만 한다
class WifiPane extends StatefulWidget {
  const WifiPane({super.key});

  @override
  State<WifiPane> createState() => _WifiPaneState();
}

class _WifiPaneState extends State<WifiPane> {
  final _wifi = Wifi.instance;

  bool? _powered;
  List<WifiNetwork> _list = const [];
  var _scanning = false;
  var _failedRead = false;
  String? _detail; // 상세를 보고 있는 네트워크 path
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh().then((_) => _scan());
    // 목록 읽기는 가볍지만 scan 은 무거워서 들어올 때와 [다시 찾기] 때만
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final powered = await _wifi.powered();
      final list = powered ? await _wifi.networks() : const <WifiNetwork>[];
      if (!mounted) return;
      setState(() {
        _powered = powered;
        _list = list;
        _failedRead = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failedRead = true);
    }
  }

  Future<void> _scan() async {
    if (_scanning || _powered != true) return;
    setState(() => _scanning = true);
    try {
      await _wifi.scan();
    } catch (_) {
      // 목록은 있던 대로 둔다
    }
    await _refresh();
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _setPowered(bool on) async {
    if (!on) {
      final ok = await confirmDelete(
        context,
        title: 'Wi-Fi 를 끌까요?',
        message: '월패드와 트레이·전력 장치 연결이 모두 끊겨요.\n다시 켜면 저장된 네트워크에 자동으로 붙어요',
        confirmLabel: '끄기',
        icon: Icons.wifi_off_rounded,
      );
      if (!ok) return;
    }
    try {
      await _wifi.setPowered(on);
    } catch (_) {
      if (mounted) await _message(icon: Icons.error_outline_rounded, color: Palette.pending, title: on ? 'Wi-Fi 를 켜지 못했어요' : 'Wi-Fi 를 끄지 못했어요', text: '잠시 뒤 다시 해 보세요');
    }
    if (!mounted) return;
    setState(() => _detail = null);
    await _refresh();
    if (on) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _scan();
    }
  }

  void _open(WifiNetwork n) {
    if (n.connected || n.saved) {
      setState(() => _detail = n.path);
    } else {
      _join(n);
    }
  }

  Future<void> _join(WifiNetwork? n, {WifiJoinInput? input, bool wrongKey = false}) async {
    if (n != null && !n.supported) {
      await _message(icon: Icons.lock_outline_rounded, color: Palette.warn, title: '이 네트워크는 쓸 수 없어요', text: '아이디가 필요한 회사용(802.1X) 네트워크예요');
      return;
    }
    if (n == null || (!n.open && !n.saved) || wrongKey) {
      input = await showWifiJoin(context, network: n, last: input, wrongKey: wrongKey);
      if (input == null || !mounted) return;
    }
    var target = n;
    final name = n?.name ?? input!.name!;
    if (target == null) {
      // 이름 숨긴 네트워크는 ConnMan 목록에 이름 없는 줄로 있다
      final open = input!.open;
      target = _list.where((x) => x.hidden && x.supported && x.open == open).firstOrNull;
      if (target == null) {
        await _message(icon: Icons.search_off_rounded, color: Palette.warn, title: '$name 을 찾지 못했어요', text: '공유기가 켜져 있는지, 이름이 맞는지 확인해 주세요');
        return;
      }
    }
    _progress(name);
    final result = await _wifi.join(target, passphrase: input?.passphrase, hiddenName: n == null ? name : null, ip: input?.ip, dns: input?.dns ?? const []);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await _refresh();
    if (!mounted) return;
    switch (result) {
      case JoinResult.ok:
        final now = _list.where((x) => x.connected).firstOrNull;
        await _message(
          icon: Icons.check_rounded,
          color: Palette.done,
          title: '$name 에 연결됐어요',
          text: '${now == null ? '' : 'IP ${now.ipv4.address} · '}다음부터 자동으로 연결해요\n트레이·전력 장치도 다시 붙어요',
        );
      case JoinResult.wrongKey:
        await _join(n, input: input, wrongKey: true);
      case JoinResult.failed:
        final back = _list.where((x) => x.connected).firstOrNull;
        final retry = await _message(
          icon: Icons.priority_high_rounded,
          color: Palette.warn,
          title: '연결하지 못했어요',
          text: back != null ? '공유기가 응답하지 않았어요.\n원래 쓰던 ${back.name} 에 다시 연결했어요' : '공유기가 응답하지 않았어요.\n공유기 가까이에서 다시 해 보세요',
          retry: true,
        );
        if (retry && mounted) await _join(n, input: input);
    }
  }

  Future<void> _changeIp(WifiNetwork n) async {
    final r = await showStaticIp(context, network: n.name, initial: n.staticIp ? n.ipv4Config : (n.ipv4.address.isEmpty ? null : n.ipv4), dns: n.nameservers);
    if (r == null || !mounted) return;
    // 같은 값을 다시 넣으면 ConnMan 이 연결을 잠깐 끊었다 붙인다
    final (ip, dns) = r;
    final same = ip.method == 'manual'
        ? n.staticIp && ip.address == n.ipv4Config.address && ip.netmask == n.ipv4Config.netmask && ip.gateway == n.ipv4Config.gateway && dns.join(',') == n.nameserversConfig.join(',')
        : !n.staticIp;
    if (same) return;
    try {
      await _wifi.setIp(n, ip, dns);
    } catch (_) {
      if (mounted) await _message(icon: Icons.error_outline_rounded, color: Palette.pending, title: 'IP 설정을 바꾸지 못했어요', text: '값을 다시 확인해 주세요');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await _refresh();
  }

  Future<void> _setAuto(WifiNetwork n, bool on) async {
    try {
      await _wifi.setAutoConnect(n, on);
    } catch (_) {
      // 아래 새로고침이 실제 값으로 되돌린다
    }
    await _refresh();
  }

  Future<void> _forget(WifiNetwork n) async {
    final ok = await confirmDelete(
      context,
      title: '${n.name} 를 지울까요?',
      message: n.connected
          ? '지금 연결된 네트워크예요. 지우면 월패드와 트레이·전력 장치 연결이 모두 끊기고, 다시 쓰려면 비밀번호를 새로 넣어야 해요'
          : '저장된 비밀번호와 IP 설정이 지워져요',
      confirmLabel: '지우기',
    );
    if (!ok) return;
    try {
      await _wifi.forget(n);
    } catch (_) {
      // 목록을 다시 읽으면 남아 있는지 보인다
    }
    if (!mounted) return;
    setState(() => _detail = null);
    await _refresh();
  }

  void _progress(String name) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xFF101322).withValues(alpha: 0.55),
      builder: (context) => DesignCanvas.legacy(
        child: Dialog(
          backgroundColor: Palette.dialog,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SizedBox(
            width: 440,
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 4, color: Palette.accent)),
                  const SizedBox(height: Space.l),
                  Text('$name 에 연결하는 중', style: Txt.title.copyWith(fontSize: 24)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 다시 시도를 누르면 true
  Future<bool> _message({required IconData icon, required Color color, required String title, required String text, bool retry = false}) async {
    final r = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xFF101322).withValues(alpha: 0.55),
      builder: (context) => DesignCanvas.legacy(
        child: Dialog(
          backgroundColor: Palette.dialog,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SizedBox(
            width: 440,
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: Palette.soft(color), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  const SizedBox(height: Space.l),
                  Text(title, style: Txt.title.copyWith(fontSize: 24)),
                  const SizedBox(height: Space.s),
                  Text(text, style: Txt.sub),
                  const SizedBox(height: Space.xl),
                  if (retry)
                    Row(
                      children: [
                        Expanded(child: AppButton.ghost('닫기', expand: true, onPressed: () => Navigator.pop(context, false))),
                        const SizedBox(width: Space.m),
                        Expanded(child: AppButton('다시 시도', expand: true, onPressed: () => Navigator.pop(context, true))),
                      ],
                    )
                  else
                    AppButton('확인', expand: true, onPressed: () => Navigator.pop(context, false)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final detail = _list.where((n) => n.path == _detail).firstOrNull;
    if (detail != null) return _detailView(detail);
    final connected = _list.where((n) => n.connected).firstOrNull;
    final others = [
      for (final n in _list)
        if (!n.connected && !n.hidden) n,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(
          title: 'Wi-Fi',
          action: Row(
            children: [
              if (_powered == true) ...[
                AppButton.ghost('다시 찾기', icon: Icons.refresh_rounded, loading: _scanning, onPressed: _scan),
                const SizedBox(width: Space.m),
              ],
              _PowerSwitch(on: _powered ?? false, onChanged: _powered == null ? null : _setPowered),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
        if (_failedRead)
          const EmptyNote(icon: Icons.error_outline_rounded, text: 'Wi-Fi 상태를 읽지 못했어요')
        else if (_powered == false)
          const EmptyNote(icon: Icons.wifi_off_rounded, text: 'Wi-Fi 가 꺼져 있어요 · 켜면 저장된 네트워크에 자동으로 붙어요')
        else if (_powered == null)
          const Center(child: CircularProgressIndicator(color: Palette.accent))
        else
          Expanded(
            child: ListView(
              children: [
                if (connected != null) ...[
                  _ConnectedCard(connected, onTap: () => setState(() => _detail = connected.path)),
                  const SizedBox(height: Space.l),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.s),
                  child: Row(
                    children: [
                      const Expanded(child: Text('주변 네트워크', style: Txt.section)),
                      Text(_scanning ? '찾는 중…' : '${others.length}개', style: Txt.caption),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(Space.m),
                  decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.card),
                  child: Column(
                    children: [
                      for (var i = 0; i < others.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: Space.m, endIndent: Space.m, color: Palette.line),
                        _NetworkRow(others[i], onTap: () => _open(others[i])),
                      ],
                      if (others.isNotEmpty) const SizedBox(height: Space.s),
                      Material(
                        color: Palette.soft(Palette.accent),
                        borderRadius: BorderRadius.circular(Radii.button),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Radii.button),
                          onTap: () => _join(null),
                          child: const SizedBox(
                            height: 52,
                            child: Row(
                              children: [
                                SizedBox(width: Space.l),
                                Icon(Icons.add_rounded, color: Palette.accent),
                                SizedBox(width: Space.m),
                                Text('목록에 없는 네트워크 직접 추가', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.accent)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _detailView(WifiNetwork n) {
    final dns = n.nameservers.isEmpty ? '-' : n.nameservers.join(', ');
    final info = [
      ('신호', '${n.signal} (${n.strength})'),
      ('보안', n.securityLabel),
      ('IP 주소', n.ipv4.address.isEmpty ? '-' : '${n.ipv4.address} (${n.staticIp ? '고정' : '자동'})'),
      ('서브넷', n.ipv4.netmask.isEmpty ? '-' : n.ipv4.netmask),
      ('게이트웨이', n.ipv4.gateway.isEmpty ? '-' : n.ipv4.gateway),
      ('DNS', dns),
      ('MAC 주소', n.mac.isEmpty ? '-' : n.mac),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(
          title: n.name,
          subtitle: n.connected ? '연결됨' : '저장됨',
          onBack: () => setState(() => _detail = null),
        ),
        const SizedBox(height: Space.xl),
        Expanded(
          child: ListView(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(Space.xl, Space.m, Space.xl, Space.m),
                decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.card),
                child: Wrap(
                  children: [
                    for (final (k, v) in info)
                      SizedBox(
                        width: 300,
                        height: 40,
                        child: Row(
                          children: [
                            SizedBox(width: 96, child: Text(k, style: Txt.caption)),
                            Expanded(child: Text(v, style: Txt.bodyStrong.copyWith(fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.l),
              Container(
                padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.l, Space.l),
                decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.card),
                child: Row(
                  children: [
                    const Expanded(child: Text('자동 연결', style: Txt.bodyStrong)),
                    _switch(n.autoConnect, (v) => _setAuto(n, v)),
                  ],
                ),
              ),
              const SizedBox(height: Space.xl),
              Row(
                children: [
                  if (!n.connected) ...[
                    AppButton('연결', icon: Icons.wifi_rounded, onPressed: () => _join(n)),
                    const SizedBox(width: Space.m),
                  ],
                  AppButton.ghost('IP 설정 변경', icon: Icons.tune_rounded, onPressed: () => _changeIp(n)),
                  const SizedBox(width: Space.m),
                  Material(
                    color: Palette.soft(Palette.pending),
                    borderRadius: BorderRadius.circular(Radii.button),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.button),
                      onTap: () => _forget(n),
                      child: const SizedBox(
                        height: kTouch,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 22),
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded, color: Palette.pending, size: 22),
                              SizedBox(width: Space.s),
                              Text('이 네트워크 지우기', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Palette.pending)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
