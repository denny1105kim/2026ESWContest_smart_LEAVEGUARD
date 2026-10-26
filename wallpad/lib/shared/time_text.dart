String two(int n) => n.toString().padLeft(2, '0');

String hhmm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

/// 하루 안의 분 → "07:30" (범위를 넘으면 한 바퀴 돌린다).
String minutesText(int m) {
  final v = (m % 1440 + 1440) % 1440;
  return '${two(v ~/ 60)}:${two(v % 60)}';
}

/// "07:30" → 450. 형식이 틀리면 null.
int? parseMinutes(String? hhmm) {
  final p = hhmm?.split(':');
  if (p == null || p.length != 2) return null;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  return h == null || m == null ? null : h * 60 + m;
}

/// "yyyy-MM-dd"
String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

/// "4:05"
String mmss(Duration d) => '${d.inMinutes}:${two(d.inSeconds % 60)}';

/// "09시"
String hourText(DateTime t) => '${two(t.hour)}시';

const weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

/// "10월 26일 월요일"
String dateText(DateTime t) => '${t.month}월 ${t.day}일 ${weekdayNames[t.weekday - 1]}요일';
