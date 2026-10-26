import 'dart:convert';
import 'dart:io';
import '../../shared/time_text.dart';
import 'http_text.dart';

class TodayWeather {
  final double tempC;
  final double highC;
  final double lowC;

  final int pop; // 지금부터 오늘 끝까지 최고 강수확률(%)
  final WeatherSky sky;

  final List<ForecastHour> hours;

  const TodayWeather({required this.tempC, required this.highC, required this.lowC, required this.pop, required this.sky, this.hours = const []});
}

class ForecastHour {
  final DateTime at;
  final double tempC;
  final int pop;
  final WeatherSky sky;

  const ForecastHour({required this.at, required this.tempC, required this.pop, required this.sky});
}

enum WeatherSky { clear, partlyCloudy, cloudy, rain, rainSnow, snow, shower }

extension WeatherSkyLabel on WeatherSky {
  String get label => switch (this) {
        WeatherSky.clear => '맑음',
        WeatherSky.partlyCloudy => '구름많음',
        WeatherSky.cloudy => '흐림',
        WeatherSky.rain => '비',
        WeatherSky.rainSnow => '비/눈',
        WeatherSky.snow => '눈',
        WeatherSky.shower => '소나기',
      };
}

/// 기상청 발표 시각. 발표 직후엔 자료가 없어 여유를 둔다.
class KmaBase {
  final String date; // yyyyMMdd
  final String time; // HHmm

  const KmaBase(this.date, this.time);

  @override
  bool operator ==(Object other) => other is KmaBase && other.date == date && other.time == time;

  @override
  int get hashCode => Object.hash(date, time);

  @override
  String toString() => '$date $time';

  static String ymd(DateTime t) => '${t.year}${two(t.month)}${two(t.day)}';

  // 초단기실황은 정시 자료가 40분쯤 올라온다
  static KmaBase nowcast(DateTime now) {
    final t = now.minute < 45 ? now.subtract(const Duration(hours: 1)) : now;
    return KmaBase(ymd(t), '${two(t.hour)}00');
  }

  static const _vilageHours = [2, 5, 8, 11, 14, 17, 20, 23];

  // 단기예보는 02·05·…·23시 발표 후 10분쯤 뒤 올라온다
  static KmaBase forecast(DateTime now) {
    for (final h in _vilageHours.reversed) {
      if (now.isAfter(DateTime(now.year, now.month, now.day, h, 15))) return KmaBase(ymd(now), '${two(h)}00');
    }
    return KmaBase(ymd(now.subtract(const Duration(days: 1))), '2300');
  }

  // 오늘 최저기온(TMN)은 02시 발표에만 있다
  static KmaBase minMax(DateTime now) => now.isAfter(DateTime(now.year, now.month, now.day, 2, 15))
      ? KmaBase(ymd(now), '0200')
      : KmaBase(ymd(now.subtract(const Duration(days: 1))), '2300');
}

/// 기상청 단기예보 조회서비스. 키는 디코딩 키.
class KmaWeather {
  final String serviceKey;
  final Duration timeout;

  KmaWeather(this.serviceKey, {this.timeout = const Duration(seconds: 15)});

  static const _base = 'https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0';

  Future<TodayWeather> fetchToday(int nx, int ny, {DateTime? now}) async => (await fetchDays(nx, ny, now: now)).$1;

  /// 오늘과 내일 (내일 자료가 없으면 null).
  Future<(TodayWeather, TodayWeather?)> fetchDays(int nx, int ny, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    final today = KmaBase.ymd(t);
    final fcBase = KmaBase.forecast(t), mmBase = KmaBase.minMax(t);
    final (nowcast, fc, mm) = await (
      _items('getUltraSrtNcst', KmaBase.nowcast(t), nx, ny, 20),
      _items('getVilageFcst', fcBase, nx, ny, 1000),
      mmBase == fcBase ? Future.value(null) : _items('getVilageFcst', mmBase, nx, ny, 1000),
    ).wait;
    final tomorrow = KmaBase.ymd(DateTime(t.year, t.month, t.day + 1));
    return (parseToday(nowcast, fc, mm ?? fc, today: today, hour: t.hour, now: t), parseDay(fc, mm ?? fc, day: tomorrow));
  }

  /// 하루 전체 예보. 하늘은 낮 12시 무렵 값, 자료가 없으면 null.
  static TodayWeather? parseDay(List<Map<String, dynamic>> fc, List<Map<String, dynamic>> mm, {required String day}) {
    List<double> values(List<Map<String, dynamic>> src, String cat) => [
          for (final e in src)
            if (e['category'] == cat && e['fcstDate'] == day) double.tryParse(e['fcstValue'].toString()) ?? double.nan,
        ].where((v) => !v.isNaN).toList();
    String? atNoon(String cat) {
      final c = [for (final e in fc) if (e['category'] == cat && e['fcstDate'] == day) e]
        ..sort((a, b) => ((int.parse(a['fcstTime'] as String) - 1200).abs()).compareTo((int.parse(b['fcstTime'] as String) - 1200).abs()));
      return c.firstOrNull?['fcstValue']?.toString();
    }

    final temps = [...values(mm, 'TMP'), ...values(fc, 'TMP')];
    if (temps.isEmpty) return null;
    final tmx = [...values(mm, 'TMX'), ...values(fc, 'TMX')], tmn = [...values(mm, 'TMN'), ...values(fc, 'TMN')];
    final pops = values(fc, 'POP');
    return TodayWeather(
      tempC: double.tryParse(atNoon('TMP') ?? '') ?? temps.first,
      highC: tmx.isNotEmpty ? tmx.first : temps.reduce((a, b) => a > b ? a : b),
      lowC: tmn.isNotEmpty ? tmn.first : temps.reduce((a, b) => a < b ? a : b),
      pop: pops.isEmpty ? 0 : pops.reduce((a, b) => a > b ? a : b).round(),
      sky: skyOf(pty: atNoon('PTY'), sky: atNoon('SKY')),
    );
  }

  static TodayWeather parseToday(List<Map<String, dynamic>> nowcast, List<Map<String, dynamic>> fc, List<Map<String, dynamic>> mm,
      {required String today, required int hour, DateTime? now}) {
    String? obs(String cat) => nowcast.where((e) => e['category'] == cat).firstOrNull?['obsrValue']?.toString();
    bool todayFrom(Map<String, dynamic> e, int h) => e['fcstDate'] == today && int.parse(e['fcstTime'] as String) ~/ 100 >= h;
    List<double> values(List<Map<String, dynamic>> src, String cat, int fromHour) => [
          for (final e in src)
            if (e['category'] == cat && todayFrom(e, fromHour)) double.tryParse(e['fcstValue'].toString()) ?? double.nan,
        ].where((v) => !v.isNaN).toList();

    String? nearest(String cat) {
      final c = fc.where((e) => e['category'] == cat && todayFrom(e, hour)).toList()
        ..sort((a, b) => (a['fcstTime'] as String).compareTo(b['fcstTime'] as String));
      return c.firstOrNull?['fcstValue']?.toString();
    }

    final hourTemps = values(mm, 'TMP', 0);
    final tmx = values(mm, 'TMX', 0), tmn = values(mm, 'TMN', 0);
    final temp = double.tryParse(obs('T1H') ?? '') ?? double.tryParse(nearest('TMP') ?? '');
    if (temp == null) throw const FormatException('기온 자료가 없어요');
    final high = tmx.isNotEmpty ? tmx.first : (hourTemps.isEmpty ? temp : hourTemps.reduce((a, b) => a > b ? a : b));
    final low = tmn.isNotEmpty ? tmn.first : (hourTemps.isEmpty ? temp : hourTemps.reduce((a, b) => a < b ? a : b));
    final pops = values(fc, 'POP', hour);

    // 최고·최저가 지금 기온과 어긋나 보이지 않게 맞춘다
    return TodayWeather(
      tempC: temp,
      highC: high < temp ? temp : high,
      lowC: low > temp ? temp : low,
      pop: pops.isEmpty ? 0 : pops.reduce((a, b) => a > b ? a : b).round(),
      sky: skyOf(pty: obs('PTY') ?? nearest('PTY'), sky: nearest('SKY')),
      hours: now == null ? const [] : hoursFrom(fc, now),
    );
  }

  // 시연 시각을 다음 날로 옮겨도 예보가 있도록 넉넉히 둔다
  static const hoursAhead = Duration(hours: 48);

  static List<ForecastHour> hoursFrom(List<Map<String, dynamic>> fc, DateTime now) {
    final start = DateTime(now.year, now.month, now.day, now.hour);
    final end = start.add(hoursAhead);
    final byTime = <DateTime, Map<String, String>>{};
    for (final e in fc) {
      final d = e['fcstDate'] as String?, t = e['fcstTime'] as String?;
      if (d == null || t == null || d.length != 8 || t.length != 4) continue;
      final at = DateTime(int.parse(d.substring(0, 4)), int.parse(d.substring(4, 6)), int.parse(d.substring(6, 8)), int.parse(t.substring(0, 2)));
      if (at.isBefore(start) || at.isAfter(end)) continue;
      byTime.putIfAbsent(at, () => {})[e['category'] as String] = e['fcstValue'].toString();
    }
    final out = <ForecastHour>[];
    for (final at in byTime.keys.toList()..sort()) {
      final v = byTime[at]!;
      final temp = double.tryParse(v['TMP'] ?? '');
      if (temp == null) continue;
      out.add(ForecastHour(at: at, tempC: temp, pop: int.tryParse(v['POP'] ?? '') ?? 0, sky: skyOf(pty: v['PTY'], sky: v['SKY'])));
    }
    return out;
  }

  // 강수 형태(PTY)가 하늘 상태(SKY)보다 먼저다
  static WeatherSky skyOf({String? pty, String? sky}) => switch (pty) {
        '1' || '5' => WeatherSky.rain,
        '2' || '6' => WeatherSky.rainSnow,
        '3' || '7' => WeatherSky.snow,
        '4' => WeatherSky.shower,
        _ => switch (sky) { '3' => WeatherSky.partlyCloudy, '4' => WeatherSky.cloudy, _ => WeatherSky.clear },
      };

  Future<List<Map<String, dynamic>>> _items(String op, KmaBase base, int nx, int ny, int rows) async {
    final uri = Uri.parse('$_base/$op').replace(queryParameters: {
      'serviceKey': serviceKey,
      'pageNo': '1',
      'numOfRows': '$rows',
      'dataType': 'JSON',
      'base_date': base.date,
      'base_time': base.time,
      'nx': '$nx',
      'ny': '$ny',
    });
    return parseItems(await getText(uri, timeout));
  }

  // 키가 틀리면 JSON 을 요청해도 XML 오류가 온다
  static List<Map<String, dynamic>> parseItems(String body) {
    final text = body.trimLeft();
    if (text.startsWith('<')) {
      final reason = RegExp(r'<returnAuthMsg>([^<]*)</returnAuthMsg>').firstMatch(text)?.group(1) ??
          RegExp(r'<resultMsg>([^<]*)</resultMsg>').firstMatch(text)?.group(1) ??
          '알 수 없는 응답';
      throw HttpException('기상청: $reason');
    }
    final j = jsonDecode(text) as Map<String, dynamic>;
    final header = j['response']?['header'] as Map<String, dynamic>?;
    if (header?['resultCode'] != '00') throw HttpException('기상청: ${header?['resultMsg'] ?? '오류'}');
    final items = j['response']?['body']?['items'];
    final list = items is Map ? items['item'] : null;
    return [for (final e in (list as List? ?? const [])) e as Map<String, dynamic>];
  }
}
