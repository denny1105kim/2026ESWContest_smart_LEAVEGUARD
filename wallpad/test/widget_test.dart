import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/core/data/database.dart';
import 'package:leaveguard_main/core/data/repository.dart';

void main() {
  late Directory dir;
  late AppDatabase database;
  late SqliteRepository repo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('leaveguard_test');
    database = AppDatabase()..open(path: '${dir.path}/test.db');
    repo = SqliteRepository(database);
  });

  /// 시드에는 이제 멤버가 없다 (멤버는 온보딩으로만 생긴다). 체크리스트 시험용 가족과 상황별 물건을 직접 넣는다
  ///   출근: 차키 · 지갑   외출: 지갑
  Future<void> addFamily() async {
    for (final n in ['준형', '재현', '치영']) {
      await repo.insertMember(n);
    }
    database.db.execute('''
      INSERT INTO member_checklist_items (member_id, situation_id, item_id)
      SELECT m.id, s.id, i.id FROM members m, situation s, items i
      WHERE s.name = '출근' OR i.label = 'wallet'
    ''');
  }

  tearDown(() {
    database.close();
    dir.deleteSync(recursive: true);
  });

  test('첫 실행에 시드가 들어간다 (멤버는 없다 — 온보딩으로 등록)', () async {
    expect(await repo.fetchMembers(), isEmpty);
    expect((await repo.fetchSituations()).length, 2);
    expect((await repo.fetchItems()).length, 2);
  });

  test('사용자를 추가한다', () async {
    await addFamily();
    final added = await repo.insertMember('아빠');
    expect(added.name, '아빠');

    final members = await repo.fetchMembers();
    expect(members.length, 4);
    expect(members.last.name, '아빠');
  });

  test('물건을 추가한다. label이 겹치면 null', () async {
    final added = await repo.insertItem(label: 'id_card', displayName: '사원증');
    expect(added, isNotNull);
    expect(added!.displayName, '사원증');

    final again = await repo.insertItem(label: 'id_card', displayName: '사원증');
    expect(again, isNull);
  });

  test('상황별로 챙길 물건이 다르다', () async {
    await addFamily();
    final members = await repo.fetchMembers();
    final situations = await repo.fetchSituations();
    final work = situations.firstWhere((s) => s.name == '출근');
    final out = situations.firstWhere((s) => s.name == '외출');

    final forWork = await repo.fetchChecklistItems(
      memberId: members.first.id,
      situationId: work.id,
    );
    final forOut = await repo.fetchChecklistItems(
      memberId: members.first.id,
      situationId: out.id,
    );

    expect(forWork.map((i) => i.label), containsAll(['car_key', 'wallet']));
    expect(forOut.map((i) => i.label), ['wallet']);
  });

  test('사용자를 삭제하면 체크리스트도 같이 지워진다', () async {
    await addFamily();
    final members = await repo.fetchMembers();
    final target = members.first;

    expect(await repo.deleteMember(target.id), isTrue);
    expect((await repo.fetchMembers()).length, members.length - 1);

    final situations = await repo.fetchSituations();
    final left = await repo.fetchChecklistItems(
      memberId: target.id,
      situationId: situations.first.id,
    );
    expect(left, isEmpty);

    expect(await repo.deleteMember(target.id), isFalse);
  });

  test('물건을 삭제하면 체크리스트에서도 빠진다', () async {
    await addFamily();
    final items = await repo.fetchItems();
    final carKey = items.firstWhere((i) => i.label == 'car_key');
    final members = await repo.fetchMembers();
    final situations = await repo.fetchSituations();
    final work = situations.firstWhere((s) => s.name == '출근');

    expect(await repo.deleteItem(carKey.id), isTrue);
    expect((await repo.fetchItems()).length, items.length - 1);

    final forWork = await repo.fetchChecklistItems(
      memberId: members.first.id,
      situationId: work.id,
    );
    expect(forWork.map((i) => i.label), isNot(contains('car_key')));

    expect(await repo.deleteItem(carKey.id), isFalse);
  });
}
