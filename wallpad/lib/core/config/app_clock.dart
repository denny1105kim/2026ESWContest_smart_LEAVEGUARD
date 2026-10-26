import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 화면 시각. 시연용으로 실제 시각과 다르게 맞출 수 있다. 실제 간격을 재는 곳은 DateTime.now() 를 쓴다
class AppClock {
  AppClock._();

  static Duration offset = Duration.zero;

  static DateTime now() => DateTime.now().add(offset);

  static bool get shifted => offset != Duration.zero;

  // 실제 시각으로 잰 것을 화면 시각으로
  static DateTime onScreen(DateTime real) => real.add(offset);

  static File get _file => File('${Platform.environment['HOME'] ?? '.'}/.config/leaveguard/clock.json');

  static void load() {
    try {
      if (!_file.existsSync()) return;
      final j = jsonDecode(_file.readAsStringSync());
      if (j is Map && j['offset_sec'] is int) offset = Duration(seconds: j['offset_sec'] as int);
    } catch (e) {
      debugPrint('LeaveGuard: 화면 시각을 읽지 못함 ($e)');
    }
  }

  static void set(DateTime? at) {
    final real = DateTime.now();
    offset = at == null ? Duration.zero : DateTime(at.year, at.month, at.day, at.hour, at.minute, real.second).difference(real);
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode({'offset_sec': offset.inSeconds}));
    } catch (e) {
      debugPrint('LeaveGuard: 화면 시각을 저장하지 못함 ($e)');
    }
  }
}
