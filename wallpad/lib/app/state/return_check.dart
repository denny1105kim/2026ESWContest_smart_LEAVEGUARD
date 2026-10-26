part of '../app_state.dart';

extension AppReturnCheck on AppState {
  bool returnCheckOn(String? id) => id != null && !_returnCheckOff.contains(id);

  Future<void> setReturnCheck(String id, bool on) async {
    on ? _returnCheckOff.remove(id) : _returnCheckOff.add(id);
    _changed();
    final memberId = int.tryParse(id);
    if (onBoard && memberId != null) await repo.saveReturnCheck(memberId, on);
  }

  Set<String> get returnMissing => {for (final b in myBelongings) if (!returnChecked.contains(b.id)) b.id};

  void _resetReturnCheck() {
    returnCheckOpen = false;
    returnAskLeftOut = false;
    returnCheckDone = false;
    returnChecked.clear();
  }

  void openReturnCheck() {
    final id = userId;
    if (stage != Stage.returning || id == null || returnDone || takenTodayOf(id).isEmpty) return;
    final left = {for (final b in leftOutOf(id, daysAgo: 0)) b.id};
    returnChecked
      ..clear()
      ..addAll(returnCheckDone || returnAnswered(id) ? [for (final b in myBelongings) if (!left.contains(b.id)) b.id] : const []);
    returnAskLeftOut = false;
    returnCheckOpen = true;
    _changed();
  }

  void toggleReturnItem(String belongingId) {
    if (!returnCheckOpen) return;
    returnChecked.contains(belongingId) ? returnChecked.remove(belongingId) : returnChecked.add(belongingId);
    if (returnMissing.isEmpty) returnAskLeftOut = false;
    _changed();
  }

  void finishBroughtBack(Set<String> left) {
    if (!returnCheckOpen) return;
    returnChecked
      ..clear()
      ..addAll([for (final b in myBelongings) if (!left.contains(b.id)) b.id]);
    _closeReturnCheck();
  }

  void checkAllReturned() {
    returnChecked.addAll(myBelongings.map((b) => b.id));
    confirmReturnCheck();
  }

  void confirmReturnCheck() {
    if (!returnCheckOpen) return;
    if (returnMissing.isNotEmpty) {
      returnAskLeftOut = true;
      _changed();
      return;
    }
    _closeReturnCheck();
  }


  void confirmLeftOut() {
    if (!returnCheckOpen) return;
    _closeReturnCheck();
  }

  void _closeReturnCheck() {
    final id = userId!;
    final missing = returnMissing;
    _leftOut[id] = (clock(), missing);
    final memberId = int.tryParse(id);
    if (onBoard && memberId != null) {
      final day = _dayKey();
      repo.deleteDayItems(memberId, day, 'left_out');
      for (final b in missing) {
        repo.putDayItem(memberId, day, 'left_out', b, at: clock());
      }
    }
    returnCheckOpen = false;
    returnAskLeftOut = false;
    returnCheckDone = true;
    _changed();
  }

  void addTomorrowNote(String name) {
    final id = userId;
    final n = name.trim();
    if (id == null || n.isEmpty) return;
    final today = notesOf(id, daysAgo: 0);
    if (today.any((e) => e.$2 == n)) return;
    final nid = 'n${clock().microsecondsSinceEpoch}'; // 재시작 뒤 되살린 메모와 겹치지 않게
    _notes[id] = (clock(), [...today, (nid, n)]);
    final memberId = int.tryParse(id);
    if (onBoard && memberId != null) repo.putDayItem(memberId, _dayKey(), 'note', nid, name: n, at: clock());
    _changed();
  }

  void removeTomorrowNote(String noteId) {
    final id = userId;
    if (id == null) return;
    final today = notesOf(id, daysAgo: 0);
    _notes[id] = (clock(), [for (final e in today) if (e.$1 != noteId) e]);
    final memberId = int.tryParse(id);
    if (onBoard && memberId != null) repo.deleteDayItem(memberId, _dayKey(), 'note', noteId);
    _changed();
  }

  List<String> morningMemosOf(String? id) {
    if (id == null || departed(id) || memoSeen.contains('$id:${_dayKey()}')) return const [];
    return [for (final (_, name) in notesOf(id, daysAgo: 1)) name];
  }

  void seeMemos() {
    final id = userId;
    if (id == null) return;
    memoSeen.add('$id:${_dayKey()}');
    _changed();
  }
}
