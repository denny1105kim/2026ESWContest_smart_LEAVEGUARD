import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/core/config/constants.dart';
import 'package:leaveguard_main/app/app_state.dart';
import 'package:leaveguard_main/app/models.dart';

void main() {
  late AppState s;

  setUp(() => s = AppState());
  tearDown(() => s.dispose());

  /// 문 앞 카메라 "귀가" → 인식 대신 직접 고름
  void comeIn(String id) {
    s.go(Stage.idle);
    s.returning();
    expect(s.stage, Stage.identifying);
    s.selectUser(id);
    expect(s.submitPin(AppState.devPin), PinResult.ok); // 이름을 고르면 PIN 을 맞혀야 들어간다
  }

  test('나갔다가 한참 뒤 들어오면 귀가 화면, 탭은 외출 전', () {
    s.departedAt['u1'] = DateTime.now().subtract(returnGrace + const Duration(minutes: 1));
    comeIn('u1');
    expect(s.stage, Stage.returning);
    expect(s.departed('u1'), isFalse);
  });

  test('출발 직후 다시 잡히면 귀가가 아니다 (체크 화면, 출발 기록 그대로)', () {
    final at = DateTime.now().subtract(const Duration(minutes: 2));
    s.departedAt['u1'] = at;
    comeIn('u1');
    expect(s.stage, Stage.checklist);
    expect(s.departedAt['u1'], at);
  });

  test('오늘 나간 적 없는 사람은 귀가가 아니다', () {
    comeIn('u2');
    expect(s.stage, Stage.checklist);
  });

  test('귀가 화면에서 집에 있던 사람 탭을 누르면 체크 화면으로', () {
    s.departedAt['u1'] = DateTime.now().subtract(const Duration(hours: 9));
    comeIn('u1');
    expect(s.stage, Stage.returning);
    s.switchUser('u2');
    expect(s.auth?.purpose, AuthPurpose.switchTo); // 다른 사람 화면은 본인 확인부터
    expect(s.submitPin(AppState.devPin), PinResult.ok);
    expect(s.stage, Stage.checklist);
    expect(s.userId, 'u2');
  });

  group('귀가 소지품 확인 (트레이는 방에 있어 스스로 체크)', () {
    void comeHome() {
      s.departedAt['u1'] = DateTime.now().subtract(const Duration(hours: 9));
      comeIn('u1');
      expect(s.stage, Stage.returning);
    }

    test('들어오면 창이 뜨고, 창이 떠 있는 동안은 [다 했어요]가 안 된다', () {
      comeHome();
      expect(s.returnCheckOpen, isTrue);
      s.finishReturn();
      expect(s.returnDone, isFalse);
      s.checkAllReturned();
      expect(s.returnCheckOpen, isFalse);
      expect(s.tomorrowListOf('u1').where((e) => e.kind == EntryKind.leftOut), isEmpty);
      s.finishReturn();
      expect(s.returnDone, isTrue);
    });

    test('안 누른 채 [확인] → 묻기. 두고 왔다고 하면 오늘 "내일 챙길 것", 다음 날 아침 "오늘 챙길 것"', () {
      comeHome();
      s.toggleReturnItem('b1'); // 지갑만 챙겨 옴
      s.confirmReturnCheck();
      expect(s.returnCheckOpen, isTrue);
      expect(s.returnAskLeftOut, isTrue);
      s.confirmLeftOut();
      expect(s.returnCheckOpen, isFalse);
      List<String> leftOut(List<ChecklistEntry> xs) => [for (final e in xs) if (e.kind == EntryKind.leftOut) e.name];
      expect(leftOut(s.tomorrowListOf('u1')), ['사원증', '차 키']);
      expect(leftOut(s.todayListOf('u1')), isEmpty);
      // 다음 날
      s.clock = () => DateTime.now().add(const Duration(days: 1));
      expect(leftOut(s.todayListOf('u1')), ['사원증', '차 키']);
      expect(leftOut(s.tomorrowListOf('u1')), isEmpty);
      // 이틀 뒤엔 사라진다
      s.clock = () => DateTime.now().add(const Duration(days: 2));
      expect(leftOut(s.todayListOf('u1')), isEmpty);
    });

    test('묻는 중에 마저 누르면 묻기를 거두고, [다시 확인]은 앞서 한 답을 채워 연다', () {
      comeHome();
      s.toggleReturnItem('b1');
      s.confirmReturnCheck();
      expect(s.returnAskLeftOut, isTrue);
      s.toggleReturnItem('b2');
      s.toggleReturnItem('b3');
      expect(s.returnAskLeftOut, isFalse);
      s.toggleReturnItem('b3');
      s.confirmReturnCheck();
      s.confirmLeftOut(); // 차 키만 두고 옴
      s.openReturnCheck();
      expect(s.returnChecked, {'b1', 'b2'});
    });

    test('설정에서 끈 사람은 창이 안 뜨지만 [소지품 확인]으로 열 수 있다', () async {
      await s.setReturnCheck('u1', false);
      comeHome();
      expect(s.returnCheckOpen, isFalse);
      s.openReturnCheck();
      expect(s.returnCheckOpen, isTrue);
    });

    test('소지품이 없는 사람은 창을 띄우지 않는다', () {
      s.departedAt['u3'] = DateTime.now().subtract(const Duration(hours: 9));
      comeIn('u3');
      expect(s.stage, Stage.returning);
      expect(s.returnCheckOpen, isFalse);
    });
  });

  test('귀가 화면에서 직접 적은 것: 같은 이름·빈칸은 안 들어가고 ✕로 지우며, 다음 날 아침 "오늘 챙길 것"', () {
    s.departedAt['u1'] = DateTime.now().subtract(const Duration(hours: 9));
    comeIn('u1');
    s.addTomorrowNote(' 보조배터리 ');
    s.addTomorrowNote('보조배터리');
    s.addTomorrowNote('  ');
    s.addTomorrowNote('택배 상자');
    List<String> notes(List<ChecklistEntry> xs) => [for (final e in xs) if (e.kind == EntryKind.note) e.name];
    expect(notes(s.tomorrowListOf('u1')), ['보조배터리', '택배 상자']);
    s.removeTomorrowNote(s.tomorrowListOf('u1').firstWhere((e) => e.name == '택배 상자').id);
    expect(notes(s.tomorrowListOf('u1')), ['보조배터리']);
    s.clock = () => DateTime.now().add(const Duration(days: 1));
    expect(notes(s.todayListOf('u1')), ['보조배터리']);
    expect(notes(s.tomorrowListOf('u1')), isEmpty);
  });
}
