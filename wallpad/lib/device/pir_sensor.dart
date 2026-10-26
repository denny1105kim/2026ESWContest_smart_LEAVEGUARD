import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// GPIO17 PIR 센서.
class PirSensor {
  static const gpio = 'GPIO_17';

  static const pollEvery = Duration(milliseconds: 100);

  // 잡음 무시용 연속 HIGH 횟수
  static const confirmReads = 2;

  // 전원 직후 PIR 안정화 시간
  static const warmUp = Duration(seconds: 30);

  static const retryAfter = Duration(seconds: 5);

  static const _svc = 'com.atlas.PeripheralManager1';
  static const _pmPath = '/com/atlas/PeripheralManager1';
  static const _gpioIface = 'com.atlas.PeripheralManager1.GPIO';

  DBusClient? _client;
  DBusRemoteObject? _pin;
  Timer? _poll;
  Timer? _retry;
  DateTime? _startedAt;
  var _highReads = 0;
  var _reading = false;
  var _enabledByUs = false;

  final _motions = StreamController<void>.broadcast();

  bool active = false;
  bool ready = false;

  /// LOW → HIGH 가 확정될 때 한 번.
  Stream<void> get motions => _motions.stream;

  Future<void> start() async {
    if (_poll != null || _retry != null) return;
    _startedAt ??= DateTime.now();
    try {
      await _open();
      ready = true;
      _poll = Timer.periodic(pollEvery, (_) => _read());
    } catch (e) {
      debugPrint('LeaveGuard: PIR($gpio) 준비 실패, ${retryAfter.inSeconds}초 뒤 다시 ($e)');
      await _closeQuietly();
      _retry = Timer(retryAfter, () {
        _retry = null;
        start().ignore();
      });
    }
  }

  Future<void> _open() async {
    final bus = _client ??= DBusClient.system();
    final pm = DBusRemoteObject(bus, name: _svc, path: DBusObjectPath(_pmPath));

    // 보드마다 GPIO 이름이 다를 수 있어 목록을 남긴다
    try {
      final list = await pm.getProperty(_svc, 'Peripherals', signature: DBusSignature('a(ss)'));
      debugPrint('LeaveGuard: PeripheralManager 장치 ${list.asArray().map((s) => s.asStruct().map((v) => v.asString()).join(':')).join(', ')}');
    } catch (_) {}

    final status = await pm.callMethod(_svc, 'GetPeripheralStatus', [const DBusString(gpio)], replySignature: DBusSignature('s'));
    var path = DBusObjectPath('$_pmPath/$gpio');
    if (status.returnValues.first.asString() != 'enabled') {
      try {
        final r = await pm.callMethod(_svc, 'EnablePeripheral', [const DBusString(gpio)], replySignature: DBusSignature('o'));
        path = r.returnValues.first.asObjectPath();
        _enabledByUs = true;
      } on DBusMethodResponseException catch (e) {
        if (!e.errorName.endsWith('PeripheralAlreadyEnabled')) rethrow;
      }
    }

    final pin = _pin = DBusRemoteObject(bus, name: _svc, path: path);
    try {
      await pin.callMethod(_gpioIface, 'Open', [const DBusUint32(0)], replySignature: DBusSignature('')); // 0 = 입력
    } on DBusMethodResponseException catch (e) {
      // 앱이 죽어 열린 채로 남은 경우
      if (!e.errorName.endsWith('PeripheralBusy')) rethrow;
      await pin.callMethod(_gpioIface, 'Close', const [], replySignature: DBusSignature(''));
      await pin.callMethod(_gpioIface, 'Open', [const DBusUint32(0)], replySignature: DBusSignature(''));
    }
    debugPrint('LeaveGuard: PIR($gpio) 읽기 시작');
  }

  Future<void> _read() async {
    final pin = _pin;
    if (pin == null || _reading) return;
    _reading = true;
    try {
      final r = await pin.callMethod(_gpioIface, 'ReadValue', const [], replySignature: DBusSignature('u'));
      final high = r.returnValues.first.asUint32() != 0; // 1 = 3V = 사람 있음
      if (DateTime.now().difference(_startedAt!) < warmUp) return;
      if (!high) {
        _highReads = 0;
        active = false;
        return;
      }
      if (++_highReads == confirmReads && !active) {
        active = true;
        _motions.add(null);
      }
    } catch (e) {
      debugPrint('LeaveGuard: PIR($gpio) 읽기 실패, 다시 연다 ($e)');
      await stop();
      _retry = Timer(retryAfter, () {
        _retry = null;
        start().ignore();
      });
    } finally {
      _reading = false;
    }
  }

  Future<void> stop() async {
    _poll?.cancel();
    _poll = null;
    _retry?.cancel();
    _retry = null;
    ready = false;
    active = false;
    _highReads = 0;
    await _closeQuietly();
  }

  Future<void> _closeQuietly() async {
    final pin = _pin;
    _pin = null;
    if (pin == null) return;
    // 열기 전이면 Close 가 실패하지만 직접 켠 건 끈다
    try {
      await pin.callMethod(_gpioIface, 'Close', const [], replySignature: DBusSignature(''));
    } catch (_) {}
    if (!_enabledByUs) return;
    try {
      final pm = DBusRemoteObject(pin.client, name: _svc, path: DBusObjectPath(_pmPath));
      await pm.callMethod(_svc, 'DisablePeripheral', [const DBusString(gpio)], replySignature: DBusSignature(''));
    } catch (_) {}
    _enabledByUs = false;
  }
}
