import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/app/app.dart';
import 'package:leaveguard_main/app/app_state.dart';
import 'package:leaveguard_main/core/data/models.dart' show MemberProfile;

/// [등록 취소] 를 누르면 어디로 가나 (화면을 실제로 띄워서 누른다)
///   사용자가 없을 때 · 로그인 없이 추가할 때 → 검은 화면(대기)
///   로그인한 사람이 설정에서 추가할 때 → 그 사람의 메인 화면
void main() {
  // 예시 가족(재현 · 서연 · 도윤)과 물건. 테스트마다 되돌린다 (app 은 하나뿐이라 앞 테스트가 지운 게 남는다)
  final family = List.of(app.users);
  final things = List.of(app.belongings);

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // 테스트 글꼴(글자마다 네모)은 실제보다 넓어 줄 넘침이 난다. 여기서 볼 것은 화면 이동이라 넘침만 넘긴다
    final report = FlutterError.onError;
    FlutterError.onError = (e) {
      if (!e.toString().contains('overflowed')) report?.call(e);
    };
    addTearDown(() => FlutterError.onError = report);
    await t.pumpWidget(const LeaveGuardApp());
    await t.pumpAndSettle();
  }

  /// 이름 "민" → 얼굴(PC 에서는 저절로 찍힌다) → PIN 2468 두 번 → 근무 형태 화면
  Future<void> registerUntilWeekday(WidgetTester t) async {
    for (final k in ['ㅁ', 'ㅣ', 'ㄴ']) {
      await t.tap(find.text(k).first);
      await t.pump();
    }
    await t.tap(find.textContaining('다음').last);
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(seconds: 4)); // 얼굴 세 장
    await t.pump(const Duration(milliseconds: 300));
    for (var round = 0; round < 2; round++) {
      for (final d in ['2', '4', '6', '8']) {
        await t.tap(find.text(d).last);
        await t.pump();
      }
      await t.pump(const Duration(milliseconds: 200));
    }
    await t.pumpAndSettle();
    expect(find.text('회사에 출근해요'), findsOneWidget);
  }

  Future<void> cancel(WidgetTester t) async {
    await t.tap(find.text('등록 취소').first);
    await t.pumpAndSettle();
    await t.tap(find.text('등록 취소').last); // 확인 창의 빨간 버튼
    await t.pumpAndSettle();
  }

  void reset({bool keepUsers = true}) {
    app.users
      ..clear()
      ..addAll(keepUsers ? family : const []);
    app.belongings
      ..clear()
      ..addAll(keepUsers ? things : const []);
    app.drafts.clear();
    app.go(Stage.idle);
  }

  testWidgets('사용자가 하나도 없을 때 취소 → 검은 화면 (누르면 첫 시작 화면)', (t) async {
    reset(keepUsers: false);
    await open(t);
    app.startOnboarding(Stage.welcome);
    await t.pumpAndSettle();
    await registerUntilWeekday(t);
    await cancel(t);
    expect(app.users, isEmpty);
    expect(app.stage, Stage.idle);
    app.motion();
    expect(app.stage, Stage.welcome);
    await t.pumpAndSettle();
  });

  testWidgets('이름 화면에서 바로 취소해도 검은 화면', (t) async {
    reset(keepUsers: false);
    await open(t);
    app.startOnboarding(Stage.welcome);
    await t.pumpAndSettle();
    await cancel(t);
    expect(app.stage, Stage.idle);
  });

  testWidgets('로그인 없이 "누구세요?" 에서 추가하다 취소 → 검은 화면', (t) async {
    reset();
    await open(t);
    final before = app.users.length;
    app.startOnboarding(Stage.userSelect);
    await t.pumpAndSettle();
    await registerUntilWeekday(t);
    await cancel(t);
    expect(app.users.length, before);
    expect((app.stage, app.userId), (Stage.idle, null));
  });

  testWidgets('로그인한 사람이 설정에서 추가하다 취소 → 그 사람의 메인 화면', (t) async {
    reset();
    await open(t);
    final host = app.users.first.id;
    app.userId = host;
    app.openSettings(SettingsPane.users);
    app.startOnboarding(Stage.settings);
    await t.pumpAndSettle();
    await registerUntilWeekday(t);
    expect(app.userId, isNot(host)); // 등록 중에는 새 사람이 화면 주인
    await cancel(t);
    expect((app.stage, app.userId), (Stage.checklist, host));
    expect(app.drafts, isEmpty);
  });

  testWidgets('3분 동안 확인 창을 띄워 둔 채로 두면 창도 닫히고 검은 화면', (t) async {
    reset();
    await open(t);
    app.startOnboarding(Stage.userSelect);
    await t.pumpAndSettle();
    await t.tap(find.text('등록 취소').first);
    await t.pumpAndSettle();
    await t.pump(const Duration(minutes: 3));
    await t.pumpAndSettle();
    expect(app.stage, Stage.idle);
    expect(find.text('등록을 취소할까요?'), findsNothing);
  });

  testWidgets('설정에서 "OO님의 설정" 을 누르면 생활 패턴 목록, 줄을 누르면 고치기 창', (t) async {
    reset();
    await open(t);
    final me = app.users.first;
    app.userId = me.id;
    await app.saveProfile(me.id, const MemberProfile(weekdayPlace: 'work', scheduleMode: 'fixed', leaveTime: '08:30', returnTime: '19:00', days: 0x1F));
    app.openSettings();
    await t.pumpAndSettle();
    await t.tap(find.text('${me.name}님의 설정'));
    await t.pumpAndSettle();
    expect(find.text('생활 패턴'), findsOneWidget);
    expect(find.text('회사 출근'), findsOneWidget);
    expect(find.text('월 – 금'), findsOneWidget);

    Future<void> tap(String s) async {
      await t.tap(find.text(s).last);
      await t.pumpAndSettle();
    }

    // 근무 형태 → 학교
    await tap('근무 형태');
    await tap('학교');
    await tap('저장');
    expect(app.profiles[me.id]!.weekdayPlace, 'school');

    // 나서는 시간: 오른쪽(10분 뒤) 값을 누르고 저장. [취소] 면 그대로
    await tap('집을 나서는 시간');
    await tap('08:40');
    await tap('취소');
    expect(app.profiles[me.id]!.leaveTime, '08:30');
    await tap('집을 나서는 시간');
    await tap('08:40');
    await tap('저장');
    expect(app.profiles[me.id]!.leaveTime, '08:40');

    // 요일 → 토 더하기
    await tap('요일');
    await tap('토');
    await tap('저장');
    expect(app.profiles[me.id]!.days, 0x3F);
    expect(find.text('월 · 화 · 수 · 목 · 금 · 토'), findsOneWidget);

    // 재택근무면 시간 · 요일 줄이 숨는다
    await tap('근무 형태');
    await tap('재택근무');
    await tap('저장');
    expect(find.text('집을 나서는 시간'), findsNothing);
    expect(app.profiles[me.id]!.scheduleMode, 'none');
  });
}
