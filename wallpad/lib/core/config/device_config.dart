import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// 사람이 넣은 평문 device.json 은 처음 읽을 때 OS 키 금고로 암호화해 device.enc 로 바꾸고 지운다
class DeviceConfig {
  static String get dir => '${Platform.environment['HOME'] ?? '.'}/.config/leaveguard';

  static File get _plain => File('$dir/device.json');
  static File get _sealed => File('$dir/device.enc');

  static bool get exists => _plain.existsSync() || _sealed.existsSync();

  static Future<Map<String, dynamic>?>? _loaded;

  // 캘린더 · 날씨가 동시에 불러도 한 번만 읽는다 (둘이 동시에 암호화하지 않게)
  static Future<Map<String, dynamic>?> load() => _loaded ??= _load();

  static Future<Map<String, dynamic>?> _load() async {
    final v = KeyVault();
    try {
      if (_plain.existsSync()) return await _sealPlain(v);
      if (_sealed.existsSync()) {
        final j = jsonDecode(utf8.decode(await v.open(_sealed.readAsBytesSync())));
        return j is Map<String, dynamic> ? j : null;
      }
    } catch (e) {
      debugPrint('LeaveGuard: 설정을 읽지 못함 ($e)');
    } finally {
      await v.close();
    }
    return null;
  }

  // 금고가 안 되면 평문을 남겨 두고 이번엔 그 값을 쓴다
  static Future<Map<String, dynamic>?> _sealPlain(KeyVault v) async {
    final text = _plain.readAsStringSync();
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) return null;
    try {
      final tmp = File('${_sealed.path}.tmp')..writeAsBytesSync(await v.seal(utf8.encode(text)), flush: true);
      tmp.renameSync(_sealed.path);
      _plain.deleteSync();
    } catch (e) {
      debugPrint('LeaveGuard: 설정을 암호화하지 못함, 평문을 남겨 둠 ($e)');
    }
    return j;
  }
}

/// Atlas KeyManager 의 AES-256-GCM 키. 저장 형식: [1(버전), IV 길이, IV…, 암호문+태그…]
class KeyVault {
  static const _keyName = 'leaveguard_device';
  static const _iface = 'com.atlas.KeyManager1';
  static const _encrypt = 0, _decrypt = 1, _gcm = 32, _padNone = 1, _tagBits = 128;

  final _client = DBusClient.system();
  late final _km = DBusRemoteObject(_client, name: _iface, path: DBusObjectPath('/com/atlas/KeyManager1'));

  Future<Uint8List> seal(List<int> data) async {
    await _ensureKey();
    final (handle, iv) = await _begin(_encrypt, const []);
    final out = await _finish(handle, data);
    return Uint8List.fromList([1, iv.length, ...iv, ...out]);
  }

  Future<Uint8List> open(List<int> blob) async {
    if (blob.length < 2 || blob[0] != 1) throw const FormatException('모르는 형식');
    final ivLen = blob[1];
    final (handle, _) = await _begin(_decrypt, blob.sublist(2, 2 + ivLen));
    return Uint8List.fromList(await _finish(handle, blob.sublist(2 + ivLen)));
  }

  Future<void> close() => _client.close();

  Future<void> _ensureKey() async {
    final r = await _km.callMethod(_iface, 'CheckKeyExists', [const DBusString(_keyName)], replySignature: DBusSignature('b'));
    if (r.returnValues.first.asBoolean()) return;
    await _km.callMethod(_iface, 'GenerateAESKey', [
      const DBusString(_keyName),
      const DBusUint32(256),
      DBusArray.uint32(const [_encrypt, _decrypt]),
      DBusArray.uint32(const [_gcm]),
      DBusArray.uint32(const [_padNone]),
    ], replySignature: DBusSignature(''));
  }

  Future<(int, List<int>)> _begin(int purpose, List<int> iv) async {
    final r = await _km.callMethod(_iface, 'BeginAESKeyOperation', [
      const DBusString(_keyName),
      DBusUint32(purpose),
      const DBusUint32(_gcm),
      const DBusUint32(_padNone),
      DBusArray.byte(iv),
      const DBusUint32(_tagBits),
    ], replySignature: DBusSignature('tay'));
    return (r.returnValues[0].asUint64(), r.returnValues[1].asByteArray().toList());
  }

  Future<List<int>> _finish(int handle, List<int> data) async {
    final r = await _km.callMethod(_iface, 'FinishAESKeyOperation', [DBusUint64(handle), DBusArray.byte(data)],
        replySignature: DBusSignature('ay'));
    return r.returnValues.first.asByteArray().toList();
  }
}
