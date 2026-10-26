part of '../app_state.dart';

extension AppMembers on AppState {
  void beginMember(User u) {
    _enter(u.id);
    _changed();
  }

  Future<void> saveProfile(String id, MemberProfile p) async {
    profiles[id] = p;
    final memberId = int.tryParse(id);
    if (onBoard && memberId != null) await repo.saveProfile(memberId, p);
    _changed();
  }

  Future<void> setEssentials(String id, List<String> names) async {
    essentials[id] = List.of(names);
    final memberId = int.tryParse(id);
    if (onBoard && memberId != null) await repo.setEssentials(memberId, names);
    _changed();
  }

  Future<User> saveNewUser(String name, Map<String, List<double>> faces, String pin, {bool draft = false}) async {
    final hash = Pin.create(pin);
    if (!onBoard) {
      final user = User(_id(), name, _colorFor(users.length));
      users.add(user);
      _pins[user.id] = hash;
      if (draft) drafts.add(user.id);
      _changed();
      return user;
    }
    final member = await repo.insertMember(name, draft: draft);
    // DB 를 새로 만들면 id 가 1 부터 다시 쓰여 서버에 옛 사람의 연결이 남아 있을 수 있다
    try {
      await (await _server)?.unlink('${member.id}').timeout(const Duration(seconds: 5));
    } catch (_) {
    }
    try {
      for (final face in faces.entries) {
        await repo.saveEmbedding(memberId: member.id, pose: face.key, embedding: face.value);
      }
      await repo.savePin(member.id, hash);
    } catch (_) {
      await repo.deleteMember(member.id).catchError((_) => false);
      rethrow;
    }
    final user = User('${member.id}', member.name, _colorFor(member.id));
    users.add(user);
    _pins[user.id] = hash;
    if (draft) drafts.add(user.id);
    _changed();
    return user;
  }

  Future<User> updateDraftUser(User u, String name, Map<String, List<double>> faces, String pin) async {
    final hash = Pin.create(pin);
    final memberId = int.tryParse(u.id);
    if (onBoard && memberId != null) {
      if (name != u.name) await repo.renameMember(memberId, name);
      await repo.clearEmbeddings(memberId);
      for (final face in faces.entries) {
        await repo.saveEmbedding(memberId: memberId, pose: face.key, embedding: face.value);
      }
      await repo.savePin(memberId, hash);
    }
    final updated = User(u.id, name, u.color, calendarLinked: u.calendarLinked);
    final i = users.indexWhere((x) => x.id == u.id);
    if (i >= 0) users[i] = updated;
    _pins[u.id] = hash;
    _pinLocks.remove(u.id);
    _changed();
    return updated;
  }

  Future<void> completeMember(User u) async {
    if (!drafts.remove(u.id)) return;
    final memberId = int.tryParse(u.id);
    if (onBoard && memberId != null) await repo.finishDraftMember(memberId);
    _changed();
  }

  void discardMember(User u) {
    if (!drafts.remove(u.id)) return;
    if (userId == u.id) userId = null;
    deleteUser(u);
  }

  List<User> get listedUsers => [for (final u in users) if (!drafts.contains(u.id)) u];

  void requestDeleteUser(User u) {
    requestAuth(u.id, AuthPurpose.delete, () => deleteUser(u));
  }

  void deleteUser(User u) {
    final memberId = int.tryParse(u.id);
    if (onBoard && memberId != null) repo.deleteMember(memberId); // 얼굴도 함께 지워진다
    users.remove(u);
    // 혼자 쓰던 물건은 지우고, 공용이면 주인에서만 뺀다
    belongings.removeWhere((b) => b.userIds.length == 1 && b.ownedBy(u.id));
    for (var i = 0; i < belongings.length; i++) {
      final b = belongings[i];
      if (b.ownedBy(u.id)) belongings[i] = Belonging(b.id, [for (final x in b.userIds) if (x != u.id) x], b.name, b.icon, photos: b.photos, thumbnail: b.thumbnail, hardToDetect: b.hardToDetect);
    }
    _checks.remove(u.id);
    for (final m in <Map<String, Object>>[_situation, _lastReturnAt, departedAt, _leftOut, _notes]) {
      m.remove(u.id);
    }
    profiles.remove(u.id);
    essentials.remove(u.id);
    if (u.calendarLinked && !_devLinked.contains(u.id)) _server.then((s) => s?.unlink(u.id)).ignore();
    _devLinked.remove(u.id);
    events.remove(u.id);
    _pins.remove(u.id);
    _pinLocks.remove(u.id);
    if (u.id == userId) {
      userId = null;
      go(users.isEmpty ? Stage.welcome : Stage.userSelect);
      return;
    }
    _changed();
  }
}
