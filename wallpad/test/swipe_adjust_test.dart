import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/shared/widgets/swipe_adjust.dart';

void main() {
  /// 온보딩 시각 칸과 같은 모양(앞 값 · 지금 값 · 뒤 값, 양옆은 누르면 한 칸)을 SwipeAdjust 로 감싼다
  Future<ValueNotifier<int>> pump(WidgetTester tester, int start) async {
    final value = ValueNotifier(start);
    String t(int m) => '${(m % 1440 ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 520,
            height: 110,
            child: ValueListenableBuilder<int>(
              valueListenable: value,
              builder: (_, v, __) => SwipeAdjust(
                value: v,
                wrap: 1440,
                onChanged: (n) => value.value = n,
                child: Row(children: [
                  Expanded(child: InkWell(key: const Key('prev'), onTap: () => value.value = (v - 10 + 1440) % 1440, child: Center(child: Text(t(v - 10 + 1440))))),
                  SizedBox(width: 170, child: Center(child: Text(t(v), key: const Key('now')))),
                  Expanded(child: InkWell(key: const Key('next'), onTap: () => value.value = (v + 10) % 1440, child: Center(child: Text(t(v + 10))))),
                ]),
              ),
            ),
          ),
        ),
      ),
    ));
    return value;
  }

  test('천천히 밀면 1배, 빠를수록 더 많이 (최대 4배)', () {
    expect(SwipeAdjust.gainFor(0.2), 1);
    expect(SwipeAdjust.gainFor(1), greaterThan(2));
    expect(SwipeAdjust.gainFor(10), SwipeAdjust.maxGain);
  });

  testWidgets('천천히 왼쪽으로 120px → 세 칸(30분) 뒤', (tester) async {
    final v = await pump(tester, 510);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('now'))));
    for (var i = 1; i <= 15; i++) {
      await g.moveBy(const Offset(-8, 0), timeStamp: Duration(milliseconds: 100 * i));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await g.up(timeStamp: const Duration(milliseconds: 1700));
    await tester.pumpAndSettle();
    expect(v.value, 540);
  });

  testWidgets('같은 120px 라도 빠르게 휙 밀면 훨씬 많이 넘어가고 굴러가다 선다', (tester) async {
    final v = await pump(tester, 510);
    await tester.fling(find.byKey(const Key('now')), const Offset(-120, 0), 2500);
    await tester.pumpAndSettle();
    final moved = (v.value - 510 + 1440) % 1440;
    expect(moved, greaterThan(90)); // 천천히 120px 은 30분
    expect(moved, lessThanOrEqualTo(4 * 60)); // 끄는 동안 + 굴러가기(최대 3시간)
  });

  testWidgets('오른쪽으로 밀면 줄고 자정을 넘으면 23시대로', (tester) async {
    final v = await pump(tester, 10);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('now'))));
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(const Offset(8, 0), timeStamp: Duration(milliseconds: 100 * i));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await g.up(timeStamp: const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(v.value, 1430);
  });

  testWidgets('양옆 값을 누르는 것은 그대로 된다', (tester) async {
    final v = await pump(tester, 510);
    await tester.tap(find.byKey(const Key('next')));
    await tester.pump();
    expect(v.value, 520);
    await tester.tap(find.byKey(const Key('prev')));
    await tester.pump();
    expect(v.value, 510);
  });

  testWidgets('아무리 세게 휙 밀어도 한 번에 크게 건너뛰지 않는다', (tester) async {
    final v = await pump(tester, 510);
    await tester.fling(find.byKey(const Key('now')), const Offset(-60, 0), 8000);
    await tester.pumpAndSettle();
    final moved = (v.value - 510 + 1440) % 1440;
    expect(moved, lessThanOrEqualTo(4 * 60));
  });
}
