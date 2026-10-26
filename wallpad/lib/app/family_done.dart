import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/config/device_config.dart';
import '../shared/time_text.dart';

class FamilyDone {
  final DateTime at;
  final String? by;

  const FamilyDone(this.at, this.by);
}

// 오늘 것만 담는다: {"date": "YYYY-MM-DD", "done": {"<일정 id>": {"at": ..., "by": ...}}}. 날이 바뀌면 빈 기록으로 읽는다
class FamilyDoneStore {
  final File file;

  FamilyDoneStore([File? file]) : file = file ?? File('${DeviceConfig.dir}/family_done.json');

  Map<String, FamilyDone> load(DateTime today) {
    try {
      if (!file.existsSync()) return {};
      final j = jsonDecode(file.readAsStringSync());
      if (j is! Map<String, dynamic> || j['date'] != dayKey(today) || j['done'] is! Map<String, dynamic>) return {};
      return {
        for (final MapEntry(:key, :value) in (j['done'] as Map<String, dynamic>).entries)
          if (value is Map<String, dynamic> && DateTime.tryParse(value['at'] as String? ?? '') != null)
            key: FamilyDone(DateTime.parse(value['at'] as String), value['by'] as String?),
      };
    } catch (e) {
      debugPrint('LeaveGuard: 가족 할 일 기록을 읽지 못함 ($e)');
      return {};
    }
  }

  Future<void> save(DateTime today, Map<String, FamilyDone> done) async {
    try {
      await file.parent.create(recursive: true);
      // 쓰다 꺼져도 깨진 파일이 남지 않게 임시 파일에 쓰고 바꾼다
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'date': dayKey(today),
        'done': {
          for (final MapEntry(:key, :value) in done.entries) key: {'at': value.at.toIso8601String(), 'by': value.by},
        },
      }));
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('LeaveGuard: 가족 할 일 기록을 저장하지 못함 ($e)');
    }
  }
}
