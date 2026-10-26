import 'dart:convert';
import 'dart:io';
import '../../shared/time_text.dart';
import 'http_text.dart';

/// 환경부 기준 미세먼지 등급. 나쁜 쪽이 뒤에 온다.
enum AirGrade {
  good('좋음'),
  normal('보통'),
  bad('나쁨'),
  veryBad('매우나쁨');

  final String label;

  const AirGrade(this.label);

  bool get needsMask => index >= AirGrade.bad.index;

  AirGrade worse(AirGrade? other) => other != null && other.index > index ? other : this;

  static AirGrade ofPm25(int v) => v <= 15 ? good : v <= 35 ? normal : v <= 75 ? bad : veryBad;

  static AirGrade ofPm10(int v) => v <= 30 ? good : v <= 80 ? normal : v <= 150 ? bad : veryBad;

  static AirGrade? ofLabel(String s) => AirGrade.values.where((g) => g.label == s.trim()).firstOrNull;
}

/// 측정소 점검 중이면 값이 null 일 수 있다.
class AirNow {
  final String station;
  final int? pm10;
  final int? pm25;

  final String dataTime; // 'yyyy-MM-dd HH:mm'

  const AirNow({required this.station, this.pm10, this.pm25, required this.dataTime});

  AirGrade? get grade {
    final a = pm25 == null ? null : AirGrade.ofPm25(pm25!);
    final b = pm10 == null ? null : AirGrade.ofPm10(pm10!);
    return a == null ? b : a.worse(b);
  }
}

class AirQuality {
  final AirNow? now;
  final AirGrade? forecast;
  final AirGrade? tomorrow;

  const AirQuality({this.now, this.forecast, this.tomorrow});

  AirGrade? get grade {
    final n = now?.grade;
    return n == null ? forecast : n.worse(forecast);
  }

  /// "미세먼지 나쁨 · 초미세먼지 48㎍/㎥ · 종로구 16시"
  String get reason {
    final g = grade;
    if (g == null) return '';
    final n = now;
    if (n == null || n.grade == null || (forecast != null && forecast!.index > n.grade!.index)) return '미세먼지 ${g.label} · 오늘 예보';
    final value = n.pm25 != null ? '초미세먼지 ${n.pm25}㎍/㎥' : '미세먼지 ${n.pm10}㎍/㎥';
    final hour = RegExp(r' (\d\d):').firstMatch(n.dataTime)?.group(1);
    return ['미세먼지 ${g.label}', value, '${n.station}${hour == null ? '' : ' ${int.parse(hour)}시'}'].join(' · ');
  }
}

/// 에어코리아 대기오염정보 (공공데이터포털).
class AirKorea {
  final String serviceKey;
  final Duration timeout;

  AirKorea(this.serviceKey, {this.timeout = const Duration(seconds: 15)});

  static const _base = 'https://apis.data.go.kr/B552584/ArpltnInforInqireSvc';

  Future<AirQuality> fetch({required String sido, required String sigungu, DateTime? now}) async {
    final short = sidoShort(sido);
    final today = now ?? DateTime.now();
    // 둘 다 실패할 때만 오류
    Object? error;
    AirNow? airNow;
    AirGrade? forecast, tomorrow;
    try {
      airNow = pickStation(await _items('getCtprvnRltmMesureDnsty', {'sidoName': short, 'numOfRows': '200', 'ver': '1.3'}), sigungu);
    } catch (e) {
      error = e;
    }
    try {
      final ymd = dayKey(today);
      // 오늘 발표에 내일 예보도 들어 있다
      final items = await _items('getMinuDustFrcstDspth', {'searchDate': ymd, 'numOfRows': '20'});
      forecast = parseForecast(items, day: ymd, sido: short);
      tomorrow = parseForecast(items, day: dayKey(DateTime(today.year, today.month, today.day + 1)), sido: short);
    } catch (e) {
      error ??= e;
    }
    if (airNow == null && forecast == null && error != null) throw error;
    return AirQuality(now: airNow, forecast: forecast, tomorrow: tomorrow);
  }

  /// '서울특별시' → '서울'
  static String sidoShort(String sido) {
    const exact = {
      '충청북도': '충북',
      '충청남도': '충남',
      '전라북도': '전북',
      '전북특별자치도': '전북',
      '전라남도': '전남',
      '경상북도': '경북',
      '경상남도': '경남',
    };
    return exact[sido] ?? (sido.length >= 2 ? sido.substring(0, 2) : sido);
  }

  /// "도시대기" 측정소 중 시·군·구 이름이 맞는 곳. 없으면 null (다른 동네 값은 쓰지 않는다).
  static AirNow? pickStation(List<Map<String, dynamic>> items, String sigungu) {
    final city = [for (final i in items) if (i['mangName'] == '도시대기') i];
    final pool = city.isEmpty ? items : city;
    // "수원시 장안구" 처럼 두 단어면 낱말별로도 찾는다
    final names = {sigungu, ...sigungu.split(' ')}.where((s) => s.isNotEmpty);
    Map<String, dynamic>? hit;
    for (final n in names) {
      hit ??= pool.where((i) => i['stationName'] == n).firstOrNull;
    }
    for (final n in names) {
      hit ??= pool.where((i) => (i['stationName'] as String? ?? '').contains(n.replaceAll(RegExp(r'[시군구]$'), ''))).firstOrNull;
    }
    if (hit == null) return null;
    return AirNow(
      station: hit['stationName'] as String? ?? '',
      pm10: _int(hit['pm10Value']),
      pm25: _int(hit['pm25Value']),
      dataTime: hit['dataTime'] as String? ?? '',
    );
  }

  // 경기는 북부·남부, 강원은 영동·영서로 나뉘어 와서 앞이 맞는 곳을 모두 본다
  static AirGrade? parseForecast(List<Map<String, dynamic>> items, {required String day, required String sido}) {
    final regions = switch (sido) {
      '강원' => const ['영동', '영서', '강원'],
      _ => [sido],
    };
    AirGrade? worst;
    for (final i in items) {
      if (i['informData'] != day || !(i['informCode'] == 'PM10' || i['informCode'] == 'PM25')) continue;
      for (final part in (i['informGrade'] as String? ?? '').split(',')) {
        final kv = part.split(':');
        if (kv.length != 2) continue;
        final name = kv[0].trim();
        if (!regions.any((r) => name.startsWith(r))) continue;
        final g = AirGrade.ofLabel(kv[1]);
        if (g != null) worst = g.worse(worst);
      }
    }
    return worst;
  }

  Future<List<Map<String, dynamic>>> _items(String op, Map<String, String> query) async {
    final uri = Uri.parse('$_base/$op').replace(queryParameters: {'serviceKey': serviceKey, 'returnType': 'json', 'pageNo': '1', ...query});
    return parseItems(await getText(uri, timeout));
  }

  // 키 오류는 XML 이든 JSON 이든 OpenAPI_ServiceResponse 로 온다
  static List<Map<String, dynamic>> parseItems(String body) {
    final text = body.trimLeft();
    if (text.startsWith('<')) {
      final reason = RegExp(r'<returnAuthMsg>([^<]*)</returnAuthMsg>').firstMatch(text)?.group(1) ?? '알 수 없는 응답';
      throw HttpException('에어코리아: $reason');
    }
    final j = jsonDecode(text) as Map<String, dynamic>;
    final auth = j['OpenAPI_ServiceResponse']?['cmmMsgHeader'] as Map<String, dynamic>?;
    if (auth != null) throw HttpException('에어코리아: ${auth['errMsg'] ?? auth['returnAuthMsg'] ?? '오류'}');
    final header = j['response']?['header'] as Map<String, dynamic>?;
    if (header?['resultCode'] != '00') throw HttpException('에어코리아: ${header?['resultMsg'] ?? '오류'}');
    final items = j['response']?['body']?['items'];
    return [for (final e in (items is List ? items : const [])) e as Map<String, dynamic>];
  }

  // 점검 중이면 '-' 나 빈 값이 온다
  static int? _int(Object? v) => v is int ? v : int.tryParse('${v ?? ''}'.trim());
}
