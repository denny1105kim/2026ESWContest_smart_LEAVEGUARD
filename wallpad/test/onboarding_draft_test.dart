import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leaveguard_main/app/app_state.dart';
import 'package:leaveguard_main/core/data/database.dart';
import 'package:leaveguard_main/core/data/repository.dart';

/// 온보딩 중 사람은 "등록 중"(임시). 끝까지 가면 확정, 취소하면 지운다. 돌아와 다시 정하면 새로 만들지 않고 고친다
void main() {
  group('상태', () {
    late AppState s;
    setUp(() => s = AppState());
    tearDown(() => s.dispose());

    test('등록 중인 사람은 목록(사용자 고르기 · 가족 탭)에 안 보이고, 끝나면 보인다', () async {
      final u = await s.saveNewUser('민지', const {}, '2468', draft: true);
      expect(s.users.map((x) => x.id), contains(u.id));
      expect(s.listedUsers.map((x) => x.id), isNot(contains(u.id)));
      expect(s.tabOrder.map((x) => x.id), isNot(contains(u.id)));
      s.finishOnboarding(u);
      expect(s.drafts, isEmpty);
      expect(s.listedUsers.map((x) => x.id), contains(u.id));
      expect((s.stage, s.userId), (Stage.checklist, u.id));
    });

    test('PIN · 이름을 다시 정하면 같은 사람을 고친다 (사람 수는 그대로)', () async {
      final u = await s.saveNewUser('민지', const {}, '2468', draft: true);
      final count = s.users.length;
      final v = await s.updateDraftUser(u, '민지수', const {}, '1357');
      expect(s.users.length, count);
      expect(v.id, u.id);
      expect(s.userOf(u.id)!.name, '민지수');
      s.go(Stage.userSelect);
      s.selectUser(u.id);
      expect(s.submitPin('2468'), PinResult.wrong);
      expect(s.submitPin('1357'), PinResult.ok);
    });

    test('[등록 취소]: 임시로 저장한 사람과 답을 지운다', () async {
      final u = await s.saveNewUser('민지', const {}, '2468', draft: true);
      s.beginMember(u);
      await s.setEssentials(u.id, ['휴대폰']);
      s.discardMember(u);
      expect(s.userOf(u.id), isNull);
      expect(s.essentials[u.id], isNull);
      expect(s.userId, isNull);
      expect(s.drafts, isEmpty);
    });

    test('확정된 사람은 discardMember 로 지워지지 않는다', () async {
      final u = await s.saveNewUser('민지', const {}, '2468', draft: true);
      await s.completeMember(u);
      s.discardMember(u);
      expect(s.userOf(u.id), isNotNull);
    });
  });

  group('DB', () {
    late Directory dir;
    late AppDatabase db;
    late SqliteRepository repo;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('draft_db');
      db = AppDatabase()..open(path: '${dir.path}/t.db');
      repo = SqliteRepository(db);
    });
    tearDown(() {
      db.close();
      dir.deleteSync(recursive: true);
    });

    test('임시로 넣은 사람은 앱을 다시 켤 때 지워지고, 확정한 사람은 남는다', () async {
      final a = await repo.insertMember('확정', draft: true);
      await repo.finishDraftMember(a.id);
      final b = await repo.insertMember('중간에 꺼짐', draft: true);
      await repo.saveEmbedding(memberId: b.id, pose: 'front', embedding: List.filled(128, 0.1));
      expect(await repo.deleteDraftMembers(), 1);
      expect((await repo.fetchMembers()).map((m) => m.name), ['확정']);
    });

    test('이름 바꾸기 · 얼굴 지우기', () async {
      final m = await repo.insertMember('민지', draft: true);
      await repo.renameMember(m.id, '민지수');
      await repo.saveEmbedding(memberId: m.id, pose: 'front', embedding: List.filled(128, 0.1));
      await repo.clearEmbeddings(m.id);
      expect((await repo.fetchMembers()).single.name, '민지수');
      expect(await repo.fetchEmbeddingPoses(m.id), isEmpty);
    });
  });
}
