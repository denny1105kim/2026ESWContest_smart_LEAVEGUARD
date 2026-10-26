import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/features/auth/pin.dart';
import 'package:leaveguard_main/core/data/database.dart';
import 'package:leaveguard_main/core/data/repository.dart';
import 'package:leaveguard_main/app/app_state.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('PIN 해시', () {
    test('맞는 PIN 만 통과, 숫자는 저장하지 않는다', () {
      final h = Pin.create('2580', random: Random(1));
      expect(Pin.verify('2580', h), isTrue);
      expect(Pin.verify('2581', h), isFalse);
      expect(h.hash.contains('2580'), isFalse);
    });

    test('같은 PIN 이라도 사람마다 salt 가 달라 해시가 다르다', () {
      expect(Pin.create('0000').hash, isNot(Pin.create('0000').hash));
    });

    test('숫자 4자리만', () {
      expect(Pin.isValid('1234'), isTrue);
      expect(['123', '12345', '12a4', ''].any(Pin.isValid), isFalse);
      expect(() => Pin.create('12'), throwsArgumentError);
    });
  });

  group('틀림 잠금', () {
    final t0 = DateTime(2026, 10, 9, 8);

    test('4번까지는 괜찮고 5번째에 30초', () {
      final l = PinLock();
      for (var i = 0; i < 4; i++) {
        l.failed(t0);
      }
      expect(l.remaining(t0), isNull);
      expect(l.triesLeft, 1);
      l.failed(t0);
      expect(l.remaining(t0), const Duration(seconds: 30));
      expect(l.remaining(t0.add(const Duration(seconds: 30))), isNull);
    });

    test('풀린 뒤 또 틀리면 1분, 그다음 5분. 맞히면 처음으로', () {
      final l = PinLock();
      for (var i = 0; i < 5; i++) {
        l.failed(t0);
      }
      l.failed(t0);
      expect(l.remaining(t0), const Duration(minutes: 1));
      l.failed(t0);
      expect(l.remaining(t0), const Duration(minutes: 5));
      l.succeeded();
      expect(l.remaining(t0), isNull);
      expect(l.triesLeft, PinLock.freeTries);
    });
  });

  group('본인 확인 흐름', () {
    late AppState s;
    setUp(() => s = AppState());
    tearDown(() => s.dispose());

    test('이름을 고르면 PIN, 틀리면 못 들어가고 5번째에 잠긴다', () {
      s.go(Stage.userSelect);
      s.selectUser('u1');
      expect(s.auth?.purpose, AuthPurpose.pick);
      for (var i = 0; i < 4; i++) {
        expect(s.submitPin('9999'), PinResult.wrong);
      }
      expect(s.submitPin('9999'), PinResult.locked);
      expect(s.submitPin(AppState.devPin), PinResult.locked); // 잠긴 동안은 맞아도 안 된다
      expect(s.stage, Stage.userSelect);
    });

    test('가족 탭은 확인 전엔 바뀌지 않는다', () {
      s.selectUser('u1');
      s.submitPin(AppState.devPin);
      s.switchUser('u2');
      expect(s.userId, 'u1');
      s.faceVerified('u3'); // 다른 사람 얼굴로는 통과 안 됨
      expect(s.userId, 'u1');
      s.faceVerified('u2');
      expect(s.userId, 'u2');
    });

    test('지우려면 그 사람 확인. 다른 사람을 지우면 내 화면 그대로, 나를 지우면 사용자 고르기', () {
      s.selectUser('u1');
      s.submitPin(AppState.devPin);
      final u2 = s.userOf('u2')!;
      s.requestDeleteUser(u2);
      expect(s.userOf('u2'), isNotNull);
      expect(s.submitPin(AppState.devPin), PinResult.ok);
      expect(s.userOf('u2'), isNull);
      expect((s.stage, s.userId), (Stage.checklist, 'u1'));
      s.requestDeleteUser(s.userOf('u1')!);
      expect(s.submitPin(AppState.devPin), PinResult.ok);
      expect((s.stage, s.userId), (Stage.userSelect, null));
    });

    test('새 사용자는 PIN 과 함께 저장된다 (PIN 없는 사용자가 생기지 않는다)', () async {
      final user = await s.saveNewUser('민지', const {}, '2468');
      expect(s.hasPin(user.id), isTrue);
      s.finishOnboarding(user); // 온보딩 끝 → 바로 그 사람 화면
      expect(s.auth, isNull); // 등록 뒤 PIN 을 따로 묻지 않는다
      expect(s.userId, user.id);
      s.go(Stage.userSelect);
      s.selectUser(user.id);
      expect(s.submitPin('2468'), PinResult.ok);
    });

    test('PIN 은 두 번 같게 눌러야 정해진다 (만들기 화면이 확인), 정하면 들어간다', () async {
      s.requestAuth('u3', AuthPurpose.create, () => s.selectUser('u3'));
      await s.createPin('1357');
      expect(s.auth?.purpose, AuthPurpose.pick); // 이어서 한 일
      expect(s.submitPin('1357'), PinResult.ok);
      expect(s.userId, 'u3');
    });
  });

  group('DB', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('pin_db'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('예전 DB(members 에 PIN 칸 없음)를 열면 칸을 더하고, 저장한 PIN 을 다시 읽는다', () async {
      final path = '${dir.path}/old.db';
      // AppDatabase 가 처음 열릴 때 SQLite 라이브러리 위치를 정하므로 한 번 열었다 닫는다
      (AppDatabase()..open(path: '${dir.path}/warmup.db')).close();
      sqlite3.open(path)
        ..execute('CREATE TABLE members (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)')
        ..execute("INSERT INTO members (name) VALUES ('재현')")
        ..dispose();

      final db = AppDatabase()..open(path: path);
      final repo = SqliteRepository(db);
      expect(await repo.fetchPins(), isEmpty);
      final h = Pin.create('2468');
      await repo.savePin(1, h);
      final pins = await repo.fetchPins();
      expect(Pin.verify('2468', pins[1]!), isTrue);
      // 귀가 소지품 확인 창 켜기·끄기 칸도 더해진다 (기본 켜짐)
      expect(await repo.fetchReturnCheckOff(), isEmpty);
      await repo.saveReturnCheck(1, false);
      expect(await repo.fetchReturnCheckOff(), {1});
      db.close();
    });
  });
}
