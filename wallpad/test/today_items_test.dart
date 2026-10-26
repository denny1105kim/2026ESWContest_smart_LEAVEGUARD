import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/app/app_state.dart';
import 'package:leaveguard_main/app/models.dart';
import 'package:leaveguard_main/features/weather/uv_index.dart';

void main() {
  group('자외선', () {
    // 실제 응답: 종로구 2026-10-09 06시 발표
    const body = '{"response":{"header":{"resultCode":"00","resultMsg":"NORMAL_SERVICE"},"body":{"items":{"item":[{"code":"A07_2",'
        '"areaNo":"1111000000","date":"2026100906","h0":"1","h3":"5","h6":"6","h9":"2","h12":"0","h15":"0","h18":"0","h21":"0",'
        '"h24":"1","h27":"5","h30":"7","h33":"2","h66":"","h75":""}]}}}}';

    test('오늘 낮(6–18시) 중 가장 높은 값, 내일 값은 보지 않는다', () {
      final uv = KmaUv.parseToday(body, base: DateTime(2026, 10, 9, 6), today: DateTime(2026, 10, 9, 8))!;
      expect(uv.max, 6);
      expect(uv.hour, 12);
      expect(uv.label, '높음');
      expect(uv.needsSunscreen, isTrue);
    });

    test('보통(3)부터 선크림', () {
      expect(const UvToday(2, 12).needsSunscreen, isFalse);
      expect(const UvToday(3, 12).needsSunscreen, isTrue);
    });

    test('발표는 06·18시, 30분 뒤부터 쓴다', () {
      expect(KmaUv.baseTime(DateTime(2026, 10, 9, 6, 20)), DateTime(2026, 10, 8, 18));
      expect(KmaUv.baseTime(DateTime(2026, 10, 9, 8)), DateTime(2026, 10, 9, 6));
      expect(KmaUv.baseTime(DateTime(2026, 10, 9, 19)), DateTime(2026, 10, 9, 18));
    });

    test('강원·전북은 새 코드, 자료 없는 광주·전남은 null', () {
      expect(KmaUv.areaNo('강원'), '5100000000');
      expect(KmaUv.areaNo('전북'), '5200000000');
      expect(KmaUv.areaNo('광주'), isNull);
      expect(KmaUv.parseToday('{"response":{"header":{"resultCode":"99","resultMsg":"검색결과가 없습니다."}}}',
          base: DateTime(2026, 10, 9, 6), today: DateTime(2026, 10, 9, 8)), isNull);
    });
  });

  group('일교차 → 겉옷', () {
    late AppState s;
    setUp(() => s = AppState());
    tearDown(() => s.dispose());

    List<String> itemsFor(int high, int low) {
      s.weather = Weather(location: '서울', tempC: high, highC: high, lowC: low, precipProb: 0, icon: Icons.wb_sunny_rounded, label: '맑음');
      return [for (final e in s.todayListOf('u1')) if (e.id.startsWith('w_coat_')) '${e.name}|${e.reason}'];
    }

    test('5° 이하는 없음, 6–8° 얇은 겉옷, 9–12° 겉옷, 13° 이상 꼭', () {
      expect(itemsFor(20, 15), isEmpty);
      expect(itemsFor(20, 14), ['얇은 겉옷|일교차 6° · 아침 14° 낮 20°']);
      expect(itemsFor(20, 12), ['얇은 겉옷|일교차 8° · 아침 12° 낮 20°']);
      expect(itemsFor(20, 11), ['겉옷|일교차 9° · 아침 11° 낮 20°']);
      expect(itemsFor(20, 8), ['겉옷|일교차 12° · 아침 8° 낮 20°']);
      expect(itemsFor(20, 7), ['겉옷|일교차 13° · 아침 7° 낮 20° · 꼭 챙기세요']);
    });
  });
}
