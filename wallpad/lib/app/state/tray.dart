part of '../app_state.dart';

extension AppTray on AppState {
  Belonging _toBelonging(OwnedBelonging b) => Belonging('${b.id}', [for (final m in b.memberIds) '$m'], b.name, Icons.category_rounded,
      photos: b.views.where((v) => v.source != 'turn').length, thumbnail: b.thumbnail, hardToDetect: b.hardToDetect);

  Future<void> _loadBelongings() async {
    final rows = await repo.fetchBelongings();
    belongings
      ..clear()
      ..addAll(rows.map(_toBelonging));
    _rows
      ..clear()
      ..addAll({for (final b in rows) '${b.id}': b});
    _rejects
      ..clear()
      ..addAll({for (final e in (await repo.fetchRejects()).entries) '${e.key}': e.value});
    _questions.clear();
    for (final q in await repo.fetchPendingQuestions()) {
      _questions['${q.belongingId}'] = q;
    }
    // 꺼져 있던 동안의 일은 모르니 열린 구간은 restart 로 닫는다
    final now = clock();
    await repo.closeOpenPresences(now, 'restart');
    await repo.prunePresence(now.subtract(trayPresenceKeep));
    _presence
      ..clear()
      ..addAll({for (final e in (await repo.fetchPresence(now.subtract(trayPresenceKeep))).entries) '${e.key}': e.value});
    _acks.clear();
    for (final e in (await repo.fetchAcks()).entries) {
      for (final m in e.value) {
        _acks.add('${e.key}:$m');
      }
    }
    _lastReturnAt
      ..clear()
      ..addAll({for (final e in (await repo.fetchLastReturns()).entries) '${e.key}': e.value});
    _devTray.clear();
  }

  void _startTray() {
    trayOffline = true; // 첫 관측이 올 때까지는 모른다
    trayLink.changes.listen((_) => _setTrayOnline(trayLink.nodeOnline));
    trayLink.observations.listen(_onTrayObservation);
    trayLink.start().ignore();
  }

  void _setTrayOnline(bool online) {
    if (trayOffline == !online) return;
    trayOffline = !online;
    if (!online) _closeAllPresence(clock(), 'offline');
    _recomputeTray();
    _changed();
  }

  Future<void> _openPresence(String id, DateTime at) async {
    final list = _presence.putIfAbsent(id, () => []);
    if (list.any((s) => s.open)) return;
    // 다시 올려놓았으면 손으로 한 "챙김" 표시는 푼다
    final key = AppLookups.trayCheckKey(id);
    for (final o in belongingById(id)?.userIds ?? const <String>[]) {
      if (checksOf(o).contains(key)) _setCheck(o, key, false);
    }
    final dbId = int.tryParse(id);
    final seg = Presence(0, dbId ?? 0, at, null, null);
    list.add(seg);
    if (!onBoard || dbId == null) return;
    final rowId = await repo.openPresence(dbId, at);
    final i = list.indexOf(seg);
    if (i >= 0) list[i] = Presence(rowId, dbId, at, list[i].until, list[i].closedBy);
  }

  Future<void> _closePresence(String id, DateTime at, String closedBy) async {
    final list = _presence[id];
    if (list == null) return;
    final i = list.indexWhere((s) => s.open);
    if (i < 0) return;
    final s = list[i];
    final takenBy = closedBy == 'left' ? int.tryParse(userId ?? '') : null;
    list[i] = Presence(s.id, s.belongingId, s.from, at, closedBy, takenBy: takenBy);
    if (onBoard && s.id != 0) await repo.closePresence(s.id, at, closedBy, takenBy: takenBy);
  }

  void _closeAllPresence(DateTime at, String closedBy) {
    for (final id in _presence.keys) {
      _closePresence(id, at, closedBy);
    }
  }

  void _recomputeTray() {
    if (onBoard) _devTray.clear();
  }

  // 노드는 멈춘 장면을 30초마다만 다시 보니 2초 뒤 재관측을 요청한다 (5초에 한 번까지)
  void _scheduleRescan() {
    if (_rescanTimer != null) return;
    const wait = Duration(seconds: 2), every = Duration(seconds: 5);
    final since = _lastRescanAt == null ? every : DateTime.now().difference(_lastRescanAt!);
    final delay = since < every ? every - since + wait : wait;
    _rescanTimer = Timer(delay, () {
      _rescanTimer = null;
      _lastRescanAt = DateTime.now();
      trayLink.rescan().ignore();
    });
  }

  void _recordMemberEvent(String id, String kind, DateTime at) {
    final memberId = int.tryParse(id);
    if (onBoard && memberId != null) repo.insertMemberEvent(memberId, kind, at);
  }

  void _recordReturn(String id) {
    final now = clock();
    _lastReturnAt[id] = now;
    _recordMemberEvent(id, 'returned', now);
    _acks.removeWhere((k) => k.endsWith(':$id'));
    final memberId = int.tryParse(id);
    if (onBoard && memberId != null) repo.deleteAcksOfMember(memberId);
    _recomputeTray();
  }

  void openTrayPeek({List<int>? preselect}) {
    trayPreselect = preselect;
    trayPeek = true;
    _changed();
  }

  void closeTrayPeek() {
    trayPeek = false;
    trayPreselect = null;
    _changed();
  }

  void acknowledgeBelonging(String id) {
    final viewer = userId;
    if (viewer == null) return;
    final status = statusOf(id, viewer);
    final ack = status == TrayStatus.notReturned || status == TrayStatus.takenByOther;
    if (!ack && status != TrayStatus.acknowledged) return;
    final key = '$id:$viewer';
    ack ? _acks.add(key) : _acks.remove(key);
    final dbId = int.tryParse(id), memberId = int.tryParse(viewer);
    if (onBoard && dbId != null && memberId != null) ack ? repo.setAck(dbId, memberId, clock()) : repo.deleteAck(dbId, memberId);
    if (!onBoard || _devTray.containsKey(id)) {
      _devTray[id] = ack ? TrayStatus.acknowledged : (trayInfoOf(id, viewer).by != null ? TrayStatus.takenByOther : TrayStatus.notReturned);
    }
    _watchReady(() {});
  }

  List<ItemViews> _galleryFor(String spaceId) => [
        for (final e in _rows.entries)
          if (e.value.spaceId == spaceId && e.value.views.isNotEmpty) ItemViews(e.key, e.value.vectors),
      ];

  void _rematchScene() {
    final o = trayScene;
    if (o == null) return;
    final gallery = _galleryFor(o.spaceId);
    if (gallery.isEmpty) return;
    final usable = drawableCandidates(o);
    final matches = GalleryMatcher.forSpace(gallery, o.spaceId).match(usable);
    final byId = {for (final c in usable) c.id: c};
    trayMatches = {for (final m in matches) m.candidateId: m};
    trayUnknown = [for (final m in matches) if (bandOf(m) == Band.unknown) byId[m.candidateId]!];
    _scheduleRescan();
    _changed();
  }

  void _onTrayObservation(BelongingObservation o) {
    _setTrayOnline(true);
    if (!o.sceneValid || o.moving) return;
    final seq = ++_watchSeq;
    final watch = _watchTargets(o);
    if (watch.isEmpty) return _matchObservation(o, const []);
    // 직접 그린 자리에 자동 박스가 없으면 그 자리만 노드에 인코딩을 부탁한다
    _watchCandidates(o, watch).then((extra) {
      if (seq == _watchSeq) _matchObservation(o, extra);
    });
  }

  List<(String, List<int>)> _watchTargets(BelongingObservation o) {
    if (o.frameId == null) return const [];
    final boxes = [for (final c in o.candidates) c.bbox];
    return [
      for (final e in _rows.entries)
        if (e.value.watchBox case final w? when e.value.spaceId == o.spaceId && !boxes.any((b) => _overlap(b, w) > 0.3)) (e.key, w),
    ];
  }

  Future<List<ObservedCandidate>> _watchCandidates(BelongingObservation o, List<(String, List<int>)> targets) async {
    final out = <ObservedCandidate>[];
    for (final (itemId, box) in targets) {
      final enc = await trayNode.encode(o.frameId!, box);
      if (enc != null && enc.spaceId == o.spaceId) out.add(ObservedCandidate(id: AppState.watchIdBase + int.parse(itemId), bbox: enc.bbox, embedding: enc.vector));
    }
    return out;
  }

  // 겹친 넓이 ÷ 작은 박스 넓이
  static double _overlap(List<int> a, List<int> b) {
    final ix = max(0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]));
    final iy = max(0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]));
    return ix * iy / max(1, min(a[2] * a[3], b[2] * b[3]));
  }

  void _matchObservation(BelongingObservation o, List<ObservedCandidate> watch) {
    final gallery = _galleryFor(o.spaceId);
    var usable = [...drawableCandidates(o), ...watch];
    var matches = gallery.isEmpty
        ? [for (final c in usable) CandidateMatch(c.id, c.bbox, MatchDecision.unknown, null, -1, null)]
        : GalleryMatcher.forSpace(gallery, o.spaceId).match(usable);
    // 지켜보는 자리는 그 물건으로 확정될 때만 남긴다
    final kept = [for (final c in watch) if (matches.any((m) => m.candidateId == c.id && m.decision == MatchDecision.matched)) c];
    if (watch.isNotEmpty) {
      final drop = {for (final c in watch) if (!kept.contains(c)) c.id};
      usable = [for (final c in usable) if (!drop.contains(c.id)) c];
      matches = [for (final m in matches) if (!drop.contains(m.candidateId)) m];
      o = o.withCandidates(kept);
    }
    _followWatchBoxes(matches);
    trayScene = o;
    trayMatches = {for (final m in matches) m.candidateId: m};
    final byId = {for (final c in usable) c.id: c};
    trayUnknown = [for (final m in matches) if (bandOf(m) == Band.unknown) byId[m.candidateId]!];

    // 판정 창은 실제 시각으로 재고, 구간에는 화면 시각을 적는다
    final real = DateTime.now(), at = clock();
    if (gallery.isNotEmpty) {
      // "아니에요" 한 모습은 애매로 세지 않는다. 세면 그 물건이 계속 흔들림으로 묶인다
      final judged = [
        for (final m in matches)
          if (m.decision != MatchDecision.matched && m.bestItemId != null && nearReject(_rejects[m.bestItemId] ?? const [], byId[m.candidateId]!.embedding!))
            CandidateMatch(m.candidateId, m.bbox, MatchDecision.unknown, null, -1, null)
          else
            m,
      ];
      final turned = _turnedInPlace(judged, byId, real);
      final counted = [
        for (final m in judged)
          if (turned[m.candidateId] case final item?) CandidateMatch(m.candidateId, m.bbox, MatchDecision.ambiguous, null, m.askFloor, item, askFloor: m.askFloor) else m,
      ];
      for (final m in judged) {
        if (m.decision == MatchDecision.matched) {
          _lastSeenBox[m.itemId!] = m.bbox;
          _lastSeenAt[m.itemId!] = real;
        }
      }
      _trayReducer.add(o.observationId, counted, gallery.map((g) => g.itemId), real);
      for (final g in gallery) {
        final state = _trayReducer.stateOf(g.itemId, real);
        if (state == PanelState.observed) _openPresence(g.itemId, at);
        if (state == PanelState.notObserved) _closePresence(g.itemId, at, 'left');
      }
      _recomputeTray();
      final matchedNow = {for (final m in matches) if (m.decision == MatchDecision.matched) m.itemId};
      final held = turned.values.toSet();
      if (gallery.any((g) => !held.contains(g.itemId) && (_presence[g.itemId]?.any((s) => s.open) ?? false) != matchedNow.contains(g.itemId))) {
        _scheduleRescan();
      }
      final confirmed = {for (final m in matches) if (m.decision == MatchDecision.matched) m.itemId};
      for (final m in matches) {
        if (bandOf(m) == Band.ask && !confirmed.contains(m.bestItemId)) _considerQuestion(m.bestItemId!, byId[m.candidateId]!, m.best, o);
      }
      for (final e in turned.entries) {
        final m = judged.firstWhere((m) => m.candidateId == e.key);
        _considerQuestion(e.value, byId[e.key]!, m.best, o);
      }
    }
    _watchReady(() {});
  }

  Map<int, String> _turnedInPlace(List<CandidateMatch> matches, Map<int, ObservedCandidate> byId, DateTime now) {
    final matched = {for (final m in matches) if (m.decision == MatchDecision.matched) m.itemId};
    final free = [for (final m in matches) if (m.decision != MatchDecision.matched && m.best < m.askFloor) m];
    final out = <int, String>{};
    for (final e in _lastSeenBox.entries) {
      final item = e.key;
      if (matched.contains(item) || !(_presence[item]?.any((s) => s.open) ?? false)) continue;
      final seen = _lastSeenAt[item];
      if (seen == null || now.difference(seen) > _turnedHold) continue;
      for (final m in free) {
        if (out.containsKey(m.candidateId) || _overlap(m.bbox, e.value) < 0.3 || _areaRatio(m.bbox, e.value) < 0.2) continue;
        if (nearReject(_rejects[item] ?? const [], byId[m.candidateId]!.embedding!)) continue;
        out[m.candidateId] = item;
        break;
      }
    }
    return out;
  }

  static const _turnedHold = Duration(minutes: 3);

  static double _areaRatio(List<int> a, List<int> b) {
    final x = a[2] * a[3], y = b[2] * b[3];
    return min(x, y) / max(1, max(x, y));
  }

  void _followWatchBoxes(List<CandidateMatch> matches) {
    for (final m in matches) {
      if (m.decision != MatchDecision.matched || m.candidateId >= AppState.watchIdBase) continue;
      final row = _rows[m.itemId];
      final w = row?.watchBox;
      if (row == null || w == null || _overlap(w, m.bbox) > 0.5) continue;
      _rows[m.itemId!] = row.copyWith(watchBox: m.bbox);
      if (onBoard) repo.setWatchBox(row.id, m.bbox);
    }
  }

  Future<void> _considerQuestion(String itemId, ObservedCandidate c, double score, BelongingObservation o) async {
    final v = c.embedding!;
    if (nearReject(_rejects[itemId] ?? const [], v)) return;
    final old = _questions[itemId];
    if (old != null && DateTime.now().difference(old.seenAt) < const Duration(minutes: 1)) return;
    if (!_questionBusy.add(itemId)) return;
    try {
      final crop = o.frameId == null ? null : await trayNode.crop(o.frameId!, c.bbox);
      final q = await repo.putQuestion(
          belongingId: int.parse(itemId), spaceId: o.spaceId, vector: v, crop: crop, score: score, seenAt: DateTime.now());
      if (_rows.containsKey(itemId)) _questions[itemId] = q;
    } catch (_) {
    } finally {
      _questionBusy.remove(itemId);
    }
  }

  void _maybeAsk(String id) {
    if (!onBoard || _askedThisVisit.contains(id)) return;
    final now = DateTime.now();
    final mine = [
      for (final e in _questions.entries)
        if ((_rows[e.key]?.memberIds.contains(int.tryParse(id)) ?? false) && now.difference(e.value.seenAt) < Learning.questionTtl) e.value,
    ]..sort((a, b) => b.seenAt.compareTo(a.seenAt));
    if (mine.isEmpty) return;
    _askedThisVisit.add(id);
    activeQuestion = mine.first;
  }

  Belonging? belongingById(String id) => belongings.where((b) => b.id == id).firstOrNull;

  Future<void> answerQuestion(bool? yes) async {
    final q = activeQuestion;
    activeQuestion = null;
    _changed();
    if (q == null || yes == null) return;
    final itemId = '${q.belongingId}';
    _questions.remove(itemId);
    try {
      await repo.answerQuestion(q.id, yes ? 'yes' : 'no');
      if (!yes) {
        await repo.insertReject(belongingId: q.belongingId, spaceId: q.spaceId, vector: q.vector);
        _rejects.putIfAbsent(itemId, () => []).add(q.vector);
        return;
      }
      await _addView(itemId, q.spaceId, q.vector, 'confirm');
      if (DateTime.now().difference(q.seenAt) < const Duration(minutes: 2)) {
        _watchReady(() => _openPresence(itemId, clock()));
      }
    } catch (_) {
    }
  }

  Future<void> answerQuestionAs(String otherId) async {
    final q = activeQuestion;
    activeQuestion = null;
    _changed();
    if (q == null) return;
    final itemId = '${q.belongingId}';
    _questions.remove(itemId);
    try {
      await repo.answerQuestion(q.id, 'no');
      await repo.insertReject(belongingId: q.belongingId, spaceId: q.spaceId, vector: q.vector);
      _rejects.putIfAbsent(itemId, () => []).add(q.vector);
      await _addView(otherId, q.spaceId, q.vector, 'register');
      if (DateTime.now().difference(q.seenAt) < const Duration(minutes: 2)) {
        _watchReady(() => _openPresence(otherId, clock()));
      }
    } catch (_) {
    }
  }

  Future<bool> _addView(String itemId, String spaceId, Float32List v, String source) async {
    final row = _rows[itemId];
    if (row == null || row.spaceId != spaceId) return false;
    final change = planAddView(row.views, v);
    if (change == null) return false;
    final views = List.of(row.views);
    if (change.replaceViewId != null) {
      await repo.deleteBelongingView(change.replaceViewId!);
      views.removeWhere((w) => w.id == change.replaceViewId);
    }
    final id = await repo.addBelongingView(belongingId: row.id, spaceId: spaceId, vector: v, source: source);
    final latest = _rows[itemId] ?? row;
    _rows[itemId] = latest.copyWith(spaceId: spaceId, views: [
      for (final w in latest.views)
        if (w.id != change.replaceViewId) w,
      BelongingView(id, v, source),
    ]);
    final i = belongings.indexWhere((b) => b.id == itemId);
    if (i >= 0) belongings[i] = _toBelonging(_rows[itemId]!);
    _rematchScene();
    return true;
  }
}
