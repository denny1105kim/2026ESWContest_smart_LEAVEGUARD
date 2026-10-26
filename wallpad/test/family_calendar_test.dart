import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/features/calendar/calendar_server.dart';
import 'package:leaveguard_main/app/family_done.dart';

void main() {
  group('가족 캘린더 응답 읽기', () {
    test('오늘·내일을 나누고 시간을 줄여 쓴다', () {
      final d = FamilyDay.fromJson({
        'date': '2026-10-08',
        'today': [
          {'id': 'e1', 'title': ' 분리수거 내놓기 ', 'start': '2026-10-08T08:00:00+09:00', 'end': '2026-10-08T09:00:00+09:00', 'all_day': false},
          {'id': 'e2', 'title': '택배 들여놓기', 'start': '2026-10-08T19:00:00+09:00'},
        ],
        'tomorrow': [
          {'id': 'e3', 'title': '부모님 결혼기념일', 'start': '2026-10-09', 'all_day': true},
        ],
      });
      expect(d.state, FamilyCalendar.ok);
      expect([for (final e in d.today) (e.id, e.title, e.timeLabel)], [
        ('e1', '분리수거 내놓기', '08:00–09:00'),
        ('e2', '택배 들여놓기', '19:00'),
      ]);
      expect(d.tomorrow.single.timeLabel, '종일');
    });

    test('모양이 이상한 일정은 건너뛰고, id 가 없으면 제목+시작으로 만든다', () {
      final d = FamilyDay.fromJson({
        'today': [
          'oops',
          {'title': '', 'start': '2026-10-08T08:00:00+09:00'},
        ],
      });
      expect(d.today.single.title, '(제목 없음)');
      expect(d.today.single.id, '@2026-10-08T08:00:00+09:00');
      expect(d.tomorrow, isEmpty);
    });
  });

  group('가족 캘린더 서버', () {
    late HttpServer server;
    late int status;
    late Object body;
    String? auth, path;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        auth = req.headers.value(HttpHeaders.authorizationHeader);
        path = req.uri.toString();
        req.response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body));
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    CalendarServer client() =>
        CalendarServer(CalendarServerConfig(url: 'http://127.0.0.1:${server.port}', key: 'test-key'));

    test('200 이면 일정, 키와 시간대를 보낸다', () async {
      status = 200;
      body = {
        'today': [
          {'id': 'e1', 'title': '분리수거', 'all_day': true},
        ],
        'tomorrow': [],
      };
      final d = await client().fetchFamilyToday();
      expect(d.state, FamilyCalendar.ok);
      expect(d.today.single.title, '분리수거');
      expect(auth, 'Bearer test-key');
      expect(path, '/api/v1/family/calendar/today?tz=Asia%2FSeoul');
    });

    test('404 는 가족 캘린더 없음', () async {
      status = 404;
      body = {'error': 'no family calendar'};
      expect((await client().fetchFamilyToday()).state, FamilyCalendar.none);
    });

    test('409 는 다시 연동', () async {
      status = 409;
      body = {'error': 'reauth_required'};
      expect((await client().fetchFamilyToday()).state, FamilyCalendar.needsReauth);
    });

    test('그 밖의 오류는 예외 (받아 둔 일정을 지우지 않게)', () async {
      status = 500;
      body = {'error': 'boom'};
      expect(client().fetchFamilyToday(), throwsA(isA<HttpException>()));
    });
  });

  group('가족 할 일 완료 기록', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('family_done'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('오늘 저장한 것은 오늘 읽히고, 다음 날엔 비어 있다', () async {
      final store = FamilyDoneStore(File('${dir.path}/family_done.json'));
      final today = DateTime(2026, 10, 8, 8, 30);
      await store.save(today, {'e1': FamilyDone(today, '서연')});

      final read = store.load(DateTime(2026, 10, 8, 23, 59));
      expect(read['e1']?.by, '서연');
      expect(read['e1']?.at, today);
      expect(store.load(DateTime(2026, 10, 9, 0, 1)), isEmpty);
    });

    test('파일이 없거나 깨져 있어도 빈 기록', () {
      final f = File('${dir.path}/family_done.json');
      expect(FamilyDoneStore(f).load(DateTime(2026, 10, 8)), isEmpty);
      f.writeAsStringSync('{깨짐');
      expect(FamilyDoneStore(f).load(DateTime(2026, 10, 8)), isEmpty);
    });
  });
}
