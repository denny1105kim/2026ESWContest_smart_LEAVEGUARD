import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 저장용 PIN 해시 (base64)
class PinHash {
  final String hash;
  final String salt;

  const PinHash(this.hash, this.salt);
}

/// PBKDF2-HMAC-SHA256
class Pin {
  static const length = 4;

  // 틀림 잠금과 함께 쓰므로 보드에서 느리지 않을 만큼만
  static const iterations = 10000;

  static bool isValid(String pin) => RegExp('^\\d{$length}\$').hasMatch(pin);

  static PinHash create(String pin, {Random? random}) {
    if (!isValid(pin)) throw ArgumentError('PIN 은 숫자 $length자리');
    final r = random ?? Random.secure();
    final salt = [for (var i = 0; i < 16; i++) r.nextInt(256)];
    return PinHash(base64Encode(_derive(pin, salt)), base64Encode(salt));
  }

  static bool verify(String pin, PinHash stored) {
    if (!isValid(pin)) return false;
    final want = base64Decode(stored.hash);
    final got = _derive(pin, base64Decode(stored.salt));
    // 상수 시간 비교
    var diff = want.length ^ got.length;
    for (var i = 0; i < want.length && i < got.length; i++) {
      diff |= want[i] ^ got[i];
    }
    return diff == 0;
  }

  // PBKDF2 한 블록(32바이트)만 쓴다
  static List<int> _derive(String pin, List<int> salt) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = List<int>.of(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }
}

/// 5번 틀리면 잠금, 이후 틀릴 때마다 잠금이 길어진다
class PinLock {
  static const freeTries = 5;
  static const waits = [Duration(seconds: 30), Duration(minutes: 1), Duration(minutes: 5)];

  var fails = 0;
  DateTime? until;

  Duration? remaining(DateTime now) {
    final u = until;
    return u == null || !now.isBefore(u) ? null : u.difference(now);
  }

  int get triesLeft => max(0, freeTries - fails);

  void failed(DateTime now) {
    fails++;
    if (fails >= freeTries) until = now.add(waits[min(fails - freeTries, waits.length - 1)]);
  }

  void succeeded() {
    fails = 0;
    until = null;
  }
}
