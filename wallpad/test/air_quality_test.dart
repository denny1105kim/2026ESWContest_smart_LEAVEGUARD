import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/features/weather/air_quality.dart';

void main() {
  group('등급 (환경부 기준)', () {
    test('초미세먼지 15·35·75 가 경계', () {
      expect([15, 16, 35, 36, 75, 76].map(AirGrade.ofPm25).toList(),
          [AirGrade.good, AirGrade.normal, AirGrade.normal, AirGrade.bad, AirGrade.bad, AirGrade.veryBad]);
    });

    test('미세먼지 30·80·150 이 경계', () {
      expect([30, 31, 80, 81, 150, 151].map(AirGrade.ofPm10).toList(),
          [AirGrade.good, AirGrade.normal, AirGrade.normal, AirGrade.bad, AirGrade.bad, AirGrade.veryBad]);
    });

    test('나쁨부터 마스크', () {
      expect(AirGrade.normal.needsMask, isFalse);
      expect(AirGrade.bad.needsMask, isTrue);
    });
  });

  group('측정소 고르기', () {
    Map<String, dynamic> st(String name, String mang, String pm25, String pm10) =>
        {'stationName': name, 'mangName': mang, 'pm25Value': pm25, 'pm10Value': pm10, 'dataTime': '2026-10-09 16:00'};

    test('도로변대기가 아니라 시·군·구 이름이 같은 도시대기', () {
      final n = AirKorea.pickStation([
        st('종로', '도로변대기', '60', '90'),
        st('중구', '도시대기', '11', '24'),
        st('종로구', '도시대기', '48', '70'),
      ], '종로구')!;
      expect(n.station, '종로구');
      expect(n.pm25, 48);
      expect(n.grade, AirGrade.bad);
    });

    test('점검 중("-")이면 그 값은 없음, 다른 값으로 등급', () {
      final n = AirKorea.pickStation([st('중구', '도시대기', '-', '90')], '중구')!;
      expect(n.pm25, isNull);
      expect(n.grade, AirGrade.bad);
    });

    test('이름이 맞는 측정소가 없으면 다른 동네 값을 쓰지 않는다 (예보만 본다)', () {
      expect(AirKorea.pickStation([st('광교동', '도시대기', '-', '-'), st('인계동', '도시대기', '20', '40')], '수원시 장안구'), isNull);
    });
  });

  group('예보', () {
    Map<String, dynamic> f(String code, String day, String grade) => {'informCode': code, 'informData': day, 'informGrade': grade};
    const today = '2026-10-09';

    test('오늘 PM10·PM2.5 중 나쁜 쪽, 내일과 오존은 보지 않는다', () {
      final items = [
        f('PM10', today, '서울 : 보통,인천 : 좋음'),
        f('PM25', today, '서울 : 나쁨,인천 : 보통'),
        f('PM25', '2026-10-10', '서울 : 매우나쁨'),
        f('O3', today, '서울 : 매우나쁨'),
      ];
      expect(AirKorea.parseForecast(items, day: today, sido: '서울'), AirGrade.bad);
    });

    test('경기는 북부·남부 중 나쁜 쪽, 강원은 영동·영서', () {
      final items = [f('PM10', today, '경기북부 : 좋음,경기남부 : 나쁨,영동 : 보통,영서 : 좋음')];
      expect(AirKorea.parseForecast(items, day: today, sido: '경기'), AirGrade.bad);
      expect(AirKorea.parseForecast(items, day: today, sido: '강원'), AirGrade.normal);
      expect(AirKorea.parseForecast(items, day: today, sido: '제주'), isNull);
    });
  });

  test('시·도 이름 줄이기', () {
    expect(['서울특별시', '경기도', '강원특별자치도', '충청남도', '전북특별자치도', '세종특별자치시'].map(AirKorea.sidoShort).toList(),
        ['서울', '경기', '강원', '충남', '전북', '세종']);
  });

  group('마스크 이유 한 줄', () {
    test('지금 값이 더 나쁘면 값과 측정소', () {
      const q = AirQuality(now: AirNow(station: '종로구', pm25: 48, pm10: 70, dataTime: '2026-10-09 16:00'), forecast: AirGrade.normal);
      expect(q.grade, AirGrade.bad);
      expect(q.reason, '미세먼지 나쁨 · 초미세먼지 48㎍/㎥ · 종로구 16시');
    });

    test('예보가 더 나쁘면 예보라고', () {
      const q = AirQuality(now: AirNow(station: '종로구', pm25: 20, dataTime: '2026-10-09 07:00'), forecast: AirGrade.bad);
      expect(q.reason, '미세먼지 나쁨 · 오늘 예보');
    });
  });

  test('활용신청 안 된 키는 사유를 올린다', () {
    const body = '{"OpenAPI_ServiceResponse":{"cmmMsgHeader":{"errMsg":"SERVICE_KEY_IS_NOT_REGISTERED_ERROR","returnReasonCode":"30"}}}';
    expect(() => AirKorea.parseItems(body),
        throwsA(isA<HttpException>().having((e) => e.message, 'message', contains('SERVICE_KEY_IS_NOT_REGISTERED_ERROR'))));
  });
}
