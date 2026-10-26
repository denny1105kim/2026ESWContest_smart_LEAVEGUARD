part of '../app_state.dart';

// 같은 이름은 한 칸에 모은다. 공용(날씨)은 챙겨도 칸이 남고, 개인 것은 모두 챙기면 사라진다
class GroupThing {
  GroupThing(this.name, this.icon, {required this.common, this.reason = ''});

  final String name;
  final IconData icon;
  final bool common;
  final String reason;

  final marks = <(String, String, bool)>[];

  List<String> get waiting => {
        for (final (who, _, done) in marks)
          if (!done) who,
      }.toList();

  bool get done => waiting.isEmpty;

  int get total => common ? 1 : marks.map((m) => m.$1).toSet().length;
  int get doneCount => common ? (done ? 1 : 0) : total - waiting.length;
}

extension AppGroup on AppState {
  bool get inGroup => group.isNotEmpty;

  List<String> get outgoing => inGroup ? group : [if (userId != null) userId!];

  List<User> get groupCandidates => [for (final u in listedUsers) if (u.id != userId && !departed(u.id)) u];

  void openGroupPick() {
    if (userId == null) return;
    groupPick
      ..clear()
      ..addAll(group.where((id) => id != userId));
    prompt = Prompt.groupPick;
    _changed();
  }

  void toggleGroupPick(String id) {
    groupPick.contains(id) ? groupPick.remove(id) : groupPick.add(id);
    _changed();
  }

  void confirmGroupPick() {
    final me = userId;
    if (me == null || groupPick.isEmpty) return;
    group
      ..clear()
      ..add(me)
      ..addAll([for (final u in groupCandidates) if (groupPick.contains(u.id)) u.id]);
    for (final id in group) {
      if (!engaged.contains(id)) engaged.add(id);
    }
    groupPick.clear();
    prompt = Prompt.none;
    _changed();
  }

  void addToGroup(String id) {
    if (!inGroup || group.contains(id) || departed(id) || userOf(id) == null) return;
    group.add(id);
    if (!engaged.contains(id)) engaged.add(id);
    _changed();
  }

  void askEndGroup() {
    if (!inGroup) return;
    prompt = Prompt.groupEnd;
    _changed();
  }

  void endGroup() {
    group.clear();
    prompt = Prompt.none;
    _changed();
  }

  List<GroupThing> get groupThings {
    final byName = <String, GroupThing>{};
    final commons = <GroupThing>[], personal = <GroupThing>[];
    GroupThing thing(String name, IconData icon, bool common, String reason) => byName.putIfAbsent(name, () {
          final t = GroupThing(name, icon, common: common, reason: reason);
          (common ? commons : personal).add(t);
          return t;
        });
    for (final who in outgoing) {
      final checks = checksOf(who);
      for (final e in todayListOf(who)) {
        final common = const [EntryKind.weather, EntryKind.air, EntryKind.uv].contains(e.kind);
        thing(e.name, e.icon, common, common ? _shortReason(e) : e.reason).marks.add((who, e.id, checks.contains(e.id)));
      }
      // 다른 가족이 가진 것 · 어제부터 없는 것 · 미확인은 출발을 막지 않는다
      for (final b in belongingsOf(who)) {
        final status = statusOf(b.id, who);
        if (status != TrayStatus.onTray && status != TrayStatus.taken) continue;
        final key = AppLookups.trayCheckKey(b.id);
        thing(b.name, b.icon, false, '').marks.add((who, key, status == TrayStatus.taken || checks.contains(key)));
      }
    }
    return [...commons, ...personal];
  }

  static String _shortReason(ChecklistEntry e) {
    final parts = [for (final p in e.reason.split(' · ')) if (p != '날씨') p];
    if (parts.isEmpty) return '';
    return e.id.contains('umbrella') ? parts.last : parts.first;
  }

  void tapGroupThing(String name) {
    final t = groupThings.where((t) => t.name == name).firstOrNull;
    if (t == null) return;
    final undo = t.common && t.done;
    _watchReady(() {
      for (final (who, key, done) in t.marks) {
        if (undo) {
          _setCheck(who, key, false);
        } else if (!done) {
          _setCheck(who, key, true);
        }
      }
    });
  }
}
