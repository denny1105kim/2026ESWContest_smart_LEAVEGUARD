import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/app/app.dart';
import 'package:leaveguard_main/app/app_state.dart';
import 'package:leaveguard_main/app/models.dart';
import 'package:leaveguard_main/features/belongings/tray_status.dart';

/// 함께 외출: 처음 들어온 사람(재현)이 조작하고, 함께 나갈 가족은 얼굴 인식 없이 고른다
void main() {
  // 전역 app 은 테스트 밖에서 만든다 (생성자의 30분 타이머가 화면 테스트의 가짜 시계에 걸리지 않게)
  final family = List.of(app.users);

  // 예시 가족: 재현(u1) · 서연(u2) · 도윤(u3). 소지품: 지갑(u1) · 사원증(u1) · 차 키(u1, u2) · 이어폰(u2)
  Weather rainy() => Weather(location: '서울', tempC: 19, highC: 20, lowC: 18, precipProb: 90, icon: Icons.umbrella_rounded, label: '흐림, 오후에 비');

  /// 예시 소지품은 상태가 제각각이라 "트레이에 있음"이 될 때까지 돌린다
  void putOnTray(AppState s, String id) {
    while (s.statusOf(id, 'u1') != TrayStatus.onTray) {
      s.cycleTray(id);
    }
  }

  group('상태', () {
    late AppState s;
    setUp(() {
      s = AppState();
      s.weather = rainy();
      s.userId = 'u1';
      s.engaged.add('u1');
      for (final id in ['b1', 'b3', 'b4']) {
        putOnTray(s, id);
      }
    });
    tearDown(() => s.dispose());

    test('고르기 창: 아무도 안 고르면 그대로, 서연을 고르면 재현 · 서연 묶음', () {
      s.openGroupPick();
      expect(s.prompt, Prompt.groupPick);
      expect([for (final u in s.groupCandidates) u.id], ['u2', 'u3']);
      s.confirmGroupPick();
      expect(s.group, isEmpty);
      s.toggleGroupPick('u2');
      s.confirmGroupPick();
      expect(s.group, ['u1', 'u2']);
      expect(s.prompt, Prompt.none);
      expect(s.engaged, contains('u2'));
    });

    test('같은 이름은 한 칸: 공용 우산이 먼저, 차 키는 두 사람이 한 칸', () {
      s.group.addAll(['u1', 'u2']);
      final things = {for (final t in s.groupThings) t.name: t};
      expect(s.groupThings.first.name, '우산');
      expect(things['우산']!.common, isTrue);
      expect(things['우산']!.waiting, ['u1', 'u2']);
      expect(things['차 키']!.waiting, ['u1', 'u2']);
      expect(things['지갑']!.waiting, ['u1']);
      expect(things['이어폰']!.waiting, ['u2']);
      expect(things['사원증']!.done, isTrue);
      // 공용은 하나, 개인은 사람마다 하나: 우산 1 + 지갑 1 + 사원증 1 + 차 키 2 + 이어폰 1
      expect(s.groupThings.fold(0, (n, t) => n + t.total), 6);
      expect(s.groupThings.fold(0, (n, t) => n + t.doneCount), 1);
    });

    test('개인 물건을 누르면 안 챙긴 사람 모두 챙김, 공용 물건은 다시 누르면 되돌린다', () {
      s.group.addAll(['u1', 'u2']);
      s.tapGroupThing('차 키');
      expect(s.groupThings.firstWhere((t) => t.name == '차 키').done, isTrue);
      expect(s.leftOnTray('u1').map((b) => b.name), ['지갑']);
      s.tapGroupThing('우산');
      expect(s.groupThings.firstWhere((t) => t.name == '우산').done, isTrue);
      s.tapGroupThing('우산');
      expect(s.groupThings.firstWhere((t) => t.name == '우산').waiting, ['u1', 'u2']);
    });

    test('묶음 밖 가족은 바로 더하고, × 는 한 번 묻고 그만한다', () {
      s.group.addAll(['u1', 'u2']);
      s.addToGroup('u3');
      expect(s.group, ['u1', 'u2', 'u3']);
      s.askEndGroup();
      expect(s.prompt, Prompt.groupEnd);
      s.closePrompt();
      expect(s.group, hasLength(3));
      s.askEndGroup();
      s.endGroup();
      expect(s.group, isEmpty);
      expect(s.userId, 'u1');
    });

    test('혼자 외출: 트레이 소지품 아이콘을 누르면 챙김 (남은 것에서 빠진다)', () {
      expect(s.leftOnTray('u1').map((b) => b.name), containsAll(['지갑', '차 키']));
      s.takeFromTray('b1');
      expect(s.leftOnTray('u1').map((b) => b.name), isNot(contains('지갑')));
      expect(s.remainingOf('u1'), s.leftOnTray('u1').length + s.uncheckedOf('u1').length);
    });

    test('[함께 출발하기]는 묶음 모두 출발로 남긴다', () {
      s.group.addAll(['u1', 'u2']);
      s.depart();
      expect(s.departed('u1'), isTrue);
      expect(s.departed('u2'), isTrue);
      expect(s.departed('u3'), isFalse);
    });
  });

  testWidgets('화면: [함께 외출] → 서연 고르기 → 묶음 · [함께 출발하기]', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // 테스트 글꼴(글자마다 네모)은 실제보다 넓어 줄 넘침이 난다. 여기서 볼 것은 흐름이라 넘침만 넘긴다
    final report = FlutterError.onError;
    FlutterError.onError = (e) {
      if (!e.toString().contains('overflowed')) report?.call(e);
    };
    addTearDown(() => FlutterError.onError = report);
    await t.pumpWidget(const LeaveGuardApp());
    app.weather = rainy();
    app.weatherAt = DateTime.now();
    app.userId = 'u1';
    app.engaged.add('u1');
    app.go(Stage.checklist);
    await t.pumpAndSettle();

    await t.tap(find.text('함께 외출'));
    await t.pumpAndSettle();
    expect(find.text('누구와 함께 나가요?'), findsOneWidget);
    await t.tap(find.text('서연').last);
    await t.pumpAndSettle();
    await t.tap(find.text('함께 외출 · 2명'));
    await t.pumpAndSettle();

    expect(app.group, ['u1', 'u2']);
    expect(find.text('함께'), findsOneWidget);
    expect(find.text('함께 출발하기'), findsOneWidget);
    expect(find.text('재현님, 비 소식이 있어요.'), findsOneWidget);
    app.go(Stage.idle);
    await t.pumpAndSettle();
    expect(app.users, family);
  });
}
