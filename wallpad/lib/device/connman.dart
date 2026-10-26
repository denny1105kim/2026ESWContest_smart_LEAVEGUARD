import 'dart:async';

import 'package:dbus/dbus.dart';

// 쓰기 동작은 appinfo.json 의 privileged.network_manage 권한이 필요하다.
class WifiNetwork {
  final String path;
  final String name; // 이름을 숨긴 네트워크는 ''
  final String state; // idle · association · configuration · ready · online · failure · disconnect
  final int strength; // 0~100
  final List<String> security; // none · psk · wep · ieee8021x · wps
  final bool saved;
  final bool autoConnect;
  final Ipv4 ipv4;
  final Ipv4 ipv4Config;
  final List<String> nameservers;
  final List<String> nameserversConfig;
  final String mac;
  final String error; // invalid-key · connect-failed …

  const WifiNetwork({
    required this.path,
    required this.name,
    required this.state,
    required this.strength,
    required this.security,
    required this.saved,
    required this.autoConnect,
    required this.ipv4,
    required this.ipv4Config,
    required this.nameservers,
    required this.nameserversConfig,
    required this.mac,
    this.error = '',
  });

  bool get connected => state == 'ready' || state == 'online';
  bool get busy => state == 'association' || state == 'configuration';
  bool get hidden => name.isEmpty;
  bool get open => security.contains('none');

  // 802.1X 는 아이디 입력이 필요해 받지 않는다
  bool get supported => !security.contains('ieee8021x');
  int get bars => strength >= 67 ? 3 : strength >= 34 ? 2 : 1;
  String get signal => strength >= 67 ? '좋음' : strength >= 34 ? '보통' : '약함';
  String get securityLabel => open
      ? '보안 없음'
      : security.contains('psk')
          ? 'WPA2'
          : security.contains('wep')
              ? 'WEP'
              : security.join(', ').toUpperCase();
  bool get staticIp => ipv4Config.method == 'manual';

  static WifiNetwork fromDbus(String path, Map<String, DBusValue> p) {
    String str(String k) => p[k]?.asString() ?? '';
    List<String> strs(String k) => p[k]?.asStringArray().toList() ?? const [];
    Map<String, DBusValue> dict(String k) => p[k]?.asStringVariantDict() ?? const {};
    return WifiNetwork(
      path: path,
      name: str('Name'),
      state: str('State'),
      strength: p['Strength']?.asByte() ?? 0,
      security: strs('Security'),
      saved: p['Favorite']?.asBoolean() ?? false,
      autoConnect: p['AutoConnect']?.asBoolean() ?? false,
      ipv4: Ipv4.fromDbus(dict('IPv4')),
      ipv4Config: Ipv4.fromDbus(dict('IPv4.Configuration')),
      nameservers: strs('Nameservers'),
      nameserversConfig: strs('Nameservers.Configuration'),
      mac: dict('Ethernet')['Address']?.asString() ?? '',
      error: str('Error'),
    );
  }
}

class Ipv4 {
  final String method; // dhcp · manual · off
  final String address, netmask, gateway;

  const Ipv4({this.method = 'dhcp', this.address = '', this.netmask = '', this.gateway = ''});

  static const dhcp = Ipv4();

  static Ipv4 fromDbus(Map<String, DBusValue> d) {
    String s(String k) => d[k]?.asString() ?? '';
    return Ipv4(method: s('Method'), address: s('Address'), netmask: s('Netmask'), gateway: s('Gateway'));
  }

  DBusValue toDbus() => DBusDict.stringVariant({
        'Method': DBusString(method),
        if (method == 'manual') ...{
          'Address': DBusString(address),
          'Netmask': DBusString(netmask),
          'Gateway': DBusString(gateway),
        },
      });
}

enum JoinResult { ok, wrongKey, failed }

class Wifi {
  Wifi._();

  static final instance = Wifi._();

  static const _svc = 'net.connman.Service';
  static const _techPath = '/net/connman/technology/wifi';
  static const _agentPath = '/com/leaveguard/WifiAgent';

  DBusClient? _client;
  _Agent? _agent;

  DBusClient get _bus => _client ??= DBusClient.system();

  DBusRemoteObject _obj(String path) => DBusRemoteObject(_bus, name: 'net.connman', path: DBusObjectPath(path));

  Future<bool> powered() async {
    final r = await _obj(_techPath).callMethod('net.connman.Technology', 'GetProperties', const []);
    return r.returnValues.first.asStringVariantDict()['Powered']?.asBoolean() ?? false;
  }

  Future<void> setPowered(bool on) async {
    try {
      await _obj(_techPath).callMethod('net.connman.Technology', 'SetProperty', [DBusString('Powered'), DBusVariant(DBusBoolean(on))]);
    } on DBusMethodResponseException catch (e) {
      if (!e.errorName.endsWith('AlreadyEnabled') && !e.errorName.endsWith('AlreadyDisabled')) rethrow;
    }
  }

  Future<void> scan() async {
    try {
      await _obj(_techPath).callMethod('net.connman.Technology', 'Scan', const []).timeout(const Duration(seconds: 15));
    } on DBusMethodResponseException catch (e) {
      if (!e.errorName.endsWith('InProgress')) rethrow;
    } on TimeoutException {
      // 찾은 만큼만 쓴다
    }
  }

  // ConnMan 이 이미 연결·저장·신호 순으로 정렬해 준다
  Future<List<WifiNetwork>> networks() async {
    final r = await _obj('/').callMethod('net.connman.Manager', 'GetServices', const []);
    return [
      for (final s in r.returnValues.first.asArray())
        if (s.asStruct()[1].asStringVariantDict() case final p when p['Type']?.asString() == 'wifi')
          WifiNetwork.fromDbus(s.asStruct()[0].asObjectPath().value, p),
    ];
  }

  Future<WifiNetwork?> current() async {
    for (final n in await networks()) {
      if (n.connected) return n;
    }
    return null;
  }

  Future<void> setAutoConnect(WifiNetwork n, bool on) async {
    await _obj(n.path).callMethod(_svc, 'SetProperty', [DBusString('AutoConnect'), DBusVariant(DBusBoolean(on))]);
  }

  Future<void> setIp(WifiNetwork n, Ipv4 ip, List<String> dns) async {
    final o = _obj(n.path);
    await o.callMethod(_svc, 'SetProperty', [DBusString('IPv4.Configuration'), DBusVariant(ip.toDbus())]);
    await o.callMethod(_svc, 'SetProperty', [DBusString('Nameservers.Configuration'), DBusVariant(DBusArray.string(ip.method == 'manual' ? dns : const []))]);
  }

  Future<void> forget(WifiNetwork n) async {
    await _obj(n.path).callMethod(_svc, 'Remove', const []);
  }

  /// 실패하면 원래 쓰던 네트워크로 되돌린다.
  Future<JoinResult> join(WifiNetwork n, {String? passphrase, String? hiddenName, Ipv4? ip, List<String> dns = const [], Duration timeout = const Duration(seconds: 25)}) async {
    final before = await current();
    if (before?.path == n.path && ip == null) return JoinResult.ok;
    final agent = await _registerAgent();
    agent.prepare(passphrase: passphrase, name: hiddenName);
    try {
      if (ip != null) {
        try {
          await setIp(n, ip, dns);
        } on DBusMethodResponseException {
          // 처음 보는 네트워크는 연결 뒤에 정한다
        }
      }
      var ok = false;
      var why = '';
      try {
        await _obj(n.path).callMethod(_svc, 'Connect', const []).timeout(timeout);
        ok = true;
      } on DBusMethodResponseException catch (e) {
        ok = e.errorName.endsWith('AlreadyConnected');
        why = e.errorName;
      } on TimeoutException {
        ok = false;
      }
      if (ok) {
        final now = (await networks()).where((x) => x.connected).firstOrNull;
        if (now != null) {
          if (ip != null && now.ipv4Config.method != ip.method) await setIp(now, ip, dns);
          await setAutoConnect(now, true);
        }
        return JoinResult.ok;
      }
      // 비밀번호가 틀리면 에이전트가 아니라 서비스 Error 에 invalid-key 가 남는다
      final after = (await networks()).where((x) => x.path == n.path || (n.hidden && x.name == hiddenName)).firstOrNull;
      final wrong = agent.error == 'invalid-key' || after?.error == 'invalid-key' || why.endsWith('InvalidKey');
      // 새로 저장된 틀린 비밀번호는 지운다
      if (!n.saved && after != null && after.saved) await forget(after).catchError((_) {});
      if (before != null && before.path != n.path) {
        try {
          await _obj(before.path).callMethod(_svc, 'Connect', const []).timeout(timeout);
        } catch (_) {
          // 원래 네트워크도 안 되면 ConnMan 의 자동 연결에 맡긴다
        }
      }
      return wrong ? JoinResult.wrongKey : JoinResult.failed;
    } finally {
      agent.prepare();
    }
  }

  Future<_Agent> _registerAgent() async {
    final existing = _agent;
    if (existing != null) return existing;
    final agent = _Agent(DBusObjectPath(_agentPath));
    await _bus.registerObject(agent);
    await _obj('/').callMethod('net.connman.Manager', 'RegisterAgent', [agent.path]);
    return _agent = agent;
  }
}

class _Agent extends DBusObject {
  _Agent(super.path);

  String? _passphrase, _name;
  String? error;

  void prepare({String? passphrase, String? name}) {
    _passphrase = passphrase;
    _name = name;
    error = null;
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'net.connman.Agent') return DBusMethodErrorResponse.unknownInterface();
    switch (call.name) {
      case 'RequestInput':
        final fields = call.values[1].asStringVariantDict();
        final reply = <String, DBusValue>{};
        for (final field in fields.keys) {
          if (field == 'Passphrase' && _passphrase != null) reply[field] = DBusString(_passphrase!);
          if (field == 'Name' && _name != null) reply[field] = DBusString(_name!);
        }
        final needed = fields.entries.where((f) => f.value.asStringVariantDict()['Requirement']?.asString() == 'mandatory').map((f) => f.key);
        // 줄 수 없는 값을 물으면 저장된 비밀번호가 틀린 경우다
        if (needed.any((k) => !reply.containsKey(k) && k != 'WPS')) {
          if (needed.contains('Passphrase')) error = 'invalid-key';
          return DBusMethodErrorResponse('net.connman.Agent.Error.Canceled');
        }
        return DBusMethodSuccessResponse([DBusDict.stringVariant(reply)]);
      case 'ReportError':
        error = call.values[1].asString();
        return DBusMethodSuccessResponse();
      case 'Release':
      case 'Cancel':
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}
