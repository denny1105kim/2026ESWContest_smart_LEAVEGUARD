import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/app/app_state.dart';
import 'package:leaveguard_main/app/models.dart';
import 'package:leaveguard_main/core/config/constants.dart';

/// 현관 카메라가 아는 가족(재현 u1)을 알아봤을 때 귀가 화면으로 가는 길
void main() {
  // 타이머를 가짜 시계로 돌리려고 testWidgets 안에서 상태를 만든다
  Future<void> run(WidgetTester t, Future<void> Function(AppState s) body) async {
    final s = AppState();
    await body(s);
    s.dispose();
  }

  Future<void> wait(WidgetTester t, int seconds) => t.pump(Duration(seconds: seconds, milliseconds: 100));

  testWidgets('대기 화면이면 인사 2초 뒤 저절로 귀가 화면', (t) async {
    await run(t, (s) async {
      s.devDoorKnown('u1');
      expect(s.doorOffersReturn, isFalse);
      await wait(t, doorKnownHold);
      expect((s.stage, s.userId), (Stage.returning, 'u1'));
      expect(s.returnedTodayAt('u1'), isNotNull);
    });
  });

  testWidgets('다른 화면을 쓰는 중이면 [귀가 화면 열기] 를 10초 띄우고, 누르지 않으면 그대로', (t) async {
    await run(t, (s) async {
      s.userId = 'u2';
      s.go(Stage.checklist);
      s.devDoorKnown('u1');
      expect(s.doorOffersReturn, isTrue);
      await wait(t, doorKnownHold);
      expect(s.doorOffersReturn, isTrue, reason: '2초 인사 뒤에도 버튼은 남는다');
      await wait(t, doorBusyOfferHold);
      expect(s.doorOffersReturn, isFalse);
      expect((s.stage, s.userId), (Stage.checklist, 'u2'));
    });
  });

  testWidgets('[귀가 화면 열기] 를 누르면 쓰던 화면을 접고 그 사람의 귀가 화면', (t) async {
    await run(t, (s) async {
      s.userId = 'u2';
      s.group.addAll(['u2', 'u3']);
      s.go(Stage.checklist);
      s.devDoorKnown('u1');
      s.doorOpenReturn();
      expect((s.stage, s.userId), (Stage.returning, 'u1'));
      expect(s.group, isEmpty);
      expect(s.doorPhase, DoorPhase.idle);
    });
  });

  testWidgets('오늘 이미 귀가한 사람은 쓰는 중이어도 인사만', (t) async {
    await run(t, (s) async {
      s.devDoorKnown('u1');
      await wait(t, doorKnownHold);
      s.userId = 'u2';
      s.go(Stage.checklist);
      s.devDoorKnown('u1');
      expect(s.doorOffersReturn, isFalse);
      await wait(t, doorKnownHold);
      expect((s.stage, s.userId), (Stage.checklist, 'u2'));
    });
  });
}
