import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/features/weather/kma_weather.dart';

void main() {
  group('발표 시각', () {
    test('초단기실황은 45분 전이면 한 시간 전 것', () {
      expect(KmaBase.nowcast(DateTime(2026, 9, 30, 8, 44)), const KmaBase('20260930', '0700'));
      expect(KmaBase.nowcast(DateTime(2026, 9, 30, 8, 46)), const KmaBase('20260930', '0800'));
      expect(KmaBase.nowcast(DateTime(2026, 9, 30, 0, 10)), const KmaBase('20260929', '2300'));
    });

    test('단기예보는 발표 15분 뒤부터, 새벽엔 어제 23시', () {
      expect(KmaBase.forecast(DateTime(2026, 9, 30, 8, 14)), const KmaBase('20260930', '0500'));
      expect(KmaBase.forecast(DateTime(2026, 9, 30, 8, 16)), const KmaBase('20260930', '0800'));
      expect(KmaBase.forecast(DateTime(2026, 9, 30, 23, 59)), const KmaBase('20260930', '2300'));
      expect(KmaBase.forecast(DateTime(2026, 9, 30, 2, 0)), const KmaBase('20260929', '2300'));
      expect(KmaBase.forecast(DateTime(2026, 10, 1, 1, 0)), const KmaBase('20260930', '2300'));
    });

    test('최고·최저는 오늘 02시 발표, 그 전엔 어제 23시', () {
      expect(KmaBase.minMax(DateTime(2026, 9, 30, 15, 0)), const KmaBase('20260930', '0200'));
      expect(KmaBase.minMax(DateTime(2026, 9, 30, 2, 10)), const KmaBase('20260929', '2300'));
    });
  });

  group('응답 합치기', () {
    Map<String, dynamic> f(String cat, String time, String v, {String date = '20260930'}) =>
        {'category': cat, 'fcstDate': date, 'fcstTime': time, 'fcstValue': v};

    test('내일: 그날 최고·최저, 하루 중 가장 높은 강수확률, 낮 12시 하늘', () {
      const d = '20261001';
      final fc = [
        f('POP', '1800', '90'), // 오늘 것 → 빼야 함
        f('POP', '0600', '20', date: d),
        f('POP', '1500', '70', date: d),
        f('TMP', '0600', '9', date: d),
        f('TMP', '1200', '17', date: d),
        f('SKY', '0600', '1', date: d),
        f('SKY', '1200', '4', date: d),
        f('PTY', '1200', '1', date: d),
      ];
      final mm = [f('TMN', '0600', '8', date: d), f('TMX', '1500', '19', date: d)];
      final w = KmaWeather.parseDay(fc, mm, day: d)!;
      expect((w.lowC, w.highC, w.pop, w.sky), (8.0, 19.0, 70, WeatherSky.rain));
      expect(KmaWeather.parseDay(fc, mm, day: '20261003'), isNull); // 그날 자료가 없으면 모른다
    });

    test('지금 기온은 실황, 최고·최저는 02시 발표, 강수확률은 남은 시간 중 최대', () {
      final nowcast = [
        {'category': 'T1H', 'obsrValue': '18.4'},
        {'category': 'PTY', 'obsrValue': '0'},
      ];
      final fc = [
        f('POP', '0900', '90'), // 이미 지난 시간 → 빼야 함
        f('POP', '1500', '30'),
        f('POP', '1800', '60'),
        f('POP', '0900', '100', date: '20261001'), // 내일 → 빼야 함
        f('SKY', '1500', '4'),
        f('PTY', '1500', '0'),
      ];
      final mm = [f('TMN', '0600', '14.0'), f('TMX', '1500', '22.0'), f('TMP', '1500', '21.0')];
      final w = KmaWeather.parseToday(nowcast, fc, mm, today: '20260930', hour: 15);
      expect(w.tempC, 18.4);
      expect(w.highC, 22.0);
      expect(w.lowC, 14.0);
      expect(w.pop, 60);
      expect(w.sky, WeatherSky.cloudy);
    });

    test('실황에 비가 오면 하늘보다 비를 먼저 보인다', () {
      final w = KmaWeather.parseToday(
        [{'category': 'T1H', 'obsrValue': '12'}, {'category': 'PTY', 'obsrValue': '1'}],
        [f('SKY', '1500', '1')],
        [f('TMP', '1500', '12'), f('TMP', '1800', '10')],
        today: '20260930',
        hour: 15,
      );
      expect(w.sky, WeatherSky.rain);
      expect(w.sky.label, '비');
      // TMX·TMN 이 없으면 시간별 기온에서 찾는다
      expect(w.highC, 12);
      expect(w.lowC, 10);
    });
  });

  test('지금 기온이 예보 최고보다 높으면 최고를 지금 기온으로', () {
    final w = KmaWeather.parseToday(
      [{'category': 'T1H', 'obsrValue': '27.7'}],
      const [],
      [
        {'category': 'TMX', 'fcstDate': '20260930', 'fcstTime': '1500', 'fcstValue': '26.0'},
        {'category': 'TMN', 'fcstDate': '20260930', 'fcstTime': '0600', 'fcstValue': '17.0'},
      ],
      today: '20260930',
      hour: 15,
    );
    expect(w.highC, 27.7);
    expect(w.lowC, 17.0);
  });

  test('키 오류는 XML 로 와도 사유를 올린다', () {
    const xml = '<OpenAPI_ServiceResponse><cmmMsgHeader><returnAuthMsg>SERVICE_KEY_IS_NOT_REGISTERED_ERROR</returnAuthMsg>'
        '</cmmMsgHeader></OpenAPI_ServiceResponse>';
    expect(() => KmaWeather.parseItems(xml),
        throwsA(isA<HttpException>().having((e) => e.message, 'message', contains('SERVICE_KEY_IS_NOT_REGISTERED_ERROR'))));
  });

  test('JSON 오류 코드도 올린다', () {
    const body = '{"response":{"header":{"resultCode":"03","resultMsg":"NO_DATA"}}}';
    expect(() => KmaWeather.parseItems(body), throwsA(isA<HttpException>()));
  });
}
