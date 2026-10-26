import 'dart:convert';
import 'dart:io';
import '../../shared/time_text.dart';
import 'http_text.dart';

/// 낮 자외선 지수 최고값과 그 시각.
class UvToday {
  final int max;
  final int hour;

  const UvToday(this.max, this.hour);

  String get label => max <= 2 ? '낮음' : max <= 5 ? '보통' : max <= 7 ? '높음' : max <= 10 ? '매우높음' : '위험';

  // WHO 기준 3 이상이면 차단
  bool get needsSunscreen => max >= 3;
}

/// 기상청 생활기상지수 자외선 지수.
class KmaUv {
  final String serviceKey;
  final Duration timeout;

  KmaUv(this.serviceKey, {this.timeout = const Duration(seconds: 15)});

  static const _url = 'https://apis.data.go.kr/1360000/LivingWthrIdxServiceV5/getUVIdxV5';

  // 시·도 코드. 광주·전남은 이 서비스에 자료가 없다
  static const _sidoCode = {
    '서울': '11', '부산': '26', '대구': '27', '인천': '28', '대전': '30', '울산': '31', '세종': '36', //
    '경기': '41', '충북': '43', '충남': '44', '경북': '47', '경남': '48', '제주': '50', '강원': '51', '전북': '52',
  };

  /// [sidoShort] 는 '서울' 같은 줄인 이름.
  static String? areaNo(String sidoShort) {
    final c = _sidoCode[sidoShort];
    return c == null ? null : '${c}00000000';
  }

  // 06시·18시 발표, 올라올 때까지 30분 여유
  static DateTime baseTime(DateTime now) {
    final d = DateTime(now.year, now.month, now.day);
    final m = now.hour * 60 + now.minute;
    if (m >= 18 * 60 + 30) return d.add(const Duration(hours: 18));
    if (m >= 6 * 60 + 30) return d.add(const Duration(hours: 6));
    return d.subtract(const Duration(hours: 6)); // 어제 18시
  }

  Future<UvToday?> fetchToday(String sidoShort, {DateTime? now}) async => (await fetchDays(sidoShort, now: now)).$1;

  // 한 응답(h0–h75)에 오늘과 내일이 다 들어 있다
  Future<(UvToday?, UvToday?)> fetchDays(String sidoShort, {DateTime? now}) async {
    final area = areaNo(sidoShort);
    if (area == null) return (null, null);
    final t = now ?? DateTime.now();
    final base = baseTime(t);
    final uri = Uri.parse(_url).replace(queryParameters: {
      'serviceKey': serviceKey,
      'dataType': 'JSON',
      'pageNo': '1',
      'numOfRows': '1',
      'areaNo': area,
      'time': '${base.year}${two(base.month)}${two(base.day)}${two(base.hour)}',
    });
    final body = await getText(uri, timeout);
    return (parseToday(body, base: base, today: t), parseToday(body, base: base, today: DateTime(t.year, t.month, t.day + 1)));
  }

  // hN 은 발표 시각에서 N시간 뒤 값. [today] 6–18시만 본다
  static UvToday? parseToday(String body, {required DateTime base, required DateTime today}) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final auth = j['OpenAPI_ServiceResponse']?['cmmMsgHeader'] as Map<String, dynamic>?;
    if (auth != null) throw HttpException('자외선: ${auth['errMsg'] ?? '오류'}');
    final header = j['response']?['header'] as Map<String, dynamic>?;
    if (header?['resultCode'] == '99') return null; // 이 지역 자료 없음
    if (header?['resultCode'] != '00') throw HttpException('자외선: ${header?['resultMsg'] ?? '오류'}');
    final list = j['response']?['body']?['items']?['item'];
    final item = list is List && list.isNotEmpty ? list.first as Map<String, dynamic> : null;
    if (item == null) return null;
    UvToday? best;
    for (var h = 0; h <= 75; h += 3) {
      final v = int.tryParse('${item['h$h'] ?? ''}');
      if (v == null) continue;
      final at = base.add(Duration(hours: h));
      if (at.year != today.year || at.month != today.month || at.day != today.day || at.hour < 6 || at.hour > 18) continue;
      if (best == null || v > best.max) best = UvToday(v, at.hour);
    }
    return best;
  }
}
