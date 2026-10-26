import 'gallery_matcher.dart';

/// 판 위 물건 상태. 안 보인다고 챙긴 것은 아니다.
enum PanelState { observed, notObserved, uncertain, unavailable }

class _Seen {
  final String observationId;
  final bool matched;
  final bool ambiguous;

  const _Seen(this.observationId, this.matched, this.ambiguous);
}

/// 최근 [window] 번 관측 중 [need] 번 이상으로 상태를 정한다. 같은 관측은 한 번만 센다.
class StateReducer {
  final int window;
  final int need;
  final Duration ttl;

  final _history = <String, List<_Seen>>{};
  final _counted = <String>{};
  final _countedOrder = <String>[];
  DateTime? _lastValidAt;

  // 관측이 2초마다 와서 id 를 다 기억하면 계속 쌓인다
  static const _rememberIds = 64;

  StateReducer({this.window = 3, this.need = 2, this.ttl = const Duration(seconds: 20)});

  /// [items] 는 상태를 추적할 등록 물건 전체.
  void add(String observationId, List<CandidateMatch> matches, Iterable<String> items, DateTime receivedAt) {
    if (!_counted.add(observationId)) return;
    _countedOrder.add(observationId);
    if (_countedOrder.length > _rememberIds) _counted.remove(_countedOrder.removeAt(0));
    // 오래 끊겼다 오면 옛 "보임" 기록 때문에 치운 물건이 다시 있음이 되지 않게 버린다
    if (_lastValidAt != null && receivedAt.difference(_lastValidAt!) > ttl) _history.clear();
    _lastValidAt = receivedAt;
    final matched = {for (final m in matches) if (m.decision == MatchDecision.matched) m.itemId!};
    // 질문 구간 후보는 안 보임으로 세면 낯선 각도의 물건이 "챙김" 이 돼서 애매로 둔다
    final ambiguous = {
      for (final m in matches)
        if (m.decision != MatchDecision.matched && m.bestItemId != null && m.best >= m.askFloor && !matched.contains(m.bestItemId)) m.bestItemId!,
    };
    for (final id in items) {
      final h = _history.putIfAbsent(id, () => []);
      h.add(_Seen(observationId, matched.contains(id), ambiguous.contains(id)));
      if (h.length > window) h.removeAt(0);
    }
  }

  PanelState stateOf(String itemId, DateTime now) {
    final last = _lastValidAt;
    if (last == null || now.difference(last) > ttl) return PanelState.unavailable;
    final h = _history[itemId] ?? const [];
    if (h.isEmpty) return PanelState.unavailable;
    final seen = h.where((s) => s.matched).length;
    final unseen = h.where((s) => !s.matched && !s.ambiguous).length;
    if (h.last.ambiguous) return PanelState.uncertain;
    if (seen >= need) return PanelState.observed;
    if (unseen >= need) return PanelState.notObserved;
    return PanelState.uncertain;
  }
}
