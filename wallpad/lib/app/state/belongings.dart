part of '../app_state.dart';

extension AppBelongings on AppState {
  void addBelonging(String name, int photos) {
    belongings.add(Belonging(_id(), [userId!], name, Icons.category_rounded, photos: photos));
    _changed();
  }

  Future<String> saveBelonging({
    required String name,
    required List<String> ownerIds,
    required String spaceId,
    required Float32List vector,
    Uint8List? thumbnail,
    bool redBox = false,
    // 자동 박스가 못 잡을 수 있어 직접 그린 자리를 따로 지켜본다
    List<int>? watchBox,
    List<Float32List> turns = const [],
  }) async {
    final saved = await repo.insertBelonging(
        memberIds: [for (final o in ownerIds) int.parse(o)],
        name: name,
        spaceId: spaceId,
        vectors: [vector],
        thumbnail: thumbnail,
        hardToDetect: redBox,
        source: redBox ? 'redbox' : 'register',
        watchBox: redBox ? watchBox : null);
    final id = '${saved.id}';
    _rows[id] = saved;
    try {
      await _addTurns(id, spaceId, turns);
    } catch (_) {}
    belongings.add(_toBelonging(_rows[id]!));
    _openPresence(id, clock());
    _changed();
    return id;
  }

  Future<void> updateBelonging(String id, {required String name, required List<String> ownerIds}) async {
    final i = belongings.indexWhere((b) => b.id == id);
    if (i < 0 || ownerIds.isEmpty) return;
    final dbId = int.tryParse(id);
    if (onBoard && dbId != null) {
      await repo.updateBelonging(dbId, name: name, memberIds: [for (final o in ownerIds) int.parse(o)]);
      final row = _rows[id];
      if (row != null) _rows[id] = row.copyWith(memberIds: [for (final o in ownerIds) int.parse(o)], name: name);
    }
    final b = belongings[i];
    belongings[i] = Belonging(b.id, List.of(ownerIds), name, b.icon, photos: b.photos, thumbnail: b.thumbnail, hardToDetect: b.hardToDetect);
    _changed();
  }

  Belonging? lookalikeOf(int candidateId) {
    final m = trayMatches[candidateId];
    if (m == null) return null;
    final id = switch (bandOf(m)) { Band.confirmed => m.itemId, Band.ask => m.bestItemId, Band.unknown => null };
    return id == null ? null : belongingById(id);
  }

  Belonging? lookalikeOfVector(String spaceId, Float32List v) {
    final gallery = _galleryFor(spaceId);
    if (gallery.isEmpty) return null;
    final m = GalleryMatcher.forSpace(gallery, spaceId).match([ObservedCandidate(id: 0, bbox: const [0, 0, 1, 1], embedding: v)]).first;
    final id = switch (bandOf(m)) { Band.confirmed => m.itemId, Band.ask => m.bestItemId, Band.unknown => null };
    return id == null ? null : belongingById(id);
  }

  Future<void> shareBelonging(String id,
      {required String name, required List<String> ownerIds, String? spaceId, Float32List? vector, String source = 'confirm', List<Float32List> turns = const []}) async {
    await updateBelonging(id, name: name, ownerIds: ownerIds);
    if (onBoard && spaceId != null && vector != null) {
      await _addView(id, spaceId, vector, source);
      if (source == 'register') {
        try {
          await _addTurns(id, spaceId, turns);
        } catch (_) {}
      }
    }
    if (onBoard) _openPresence(id, clock());
  }

  Future<void> _addTurns(String id, String spaceId, List<Float32List> turns) async {
    final row = _rows[id];
    if (!onBoard || row == null || row.spaceId != spaceId || turns.isEmpty) return;
    final views = List.of(row.views), added = <BelongingView>[];
    for (final v in turns) {
      if (views.where((w) => w.source == 'turn').length >= Learning.maxTurns) break;
      if (views.any((w) => cosine(w.vector, v) >= Learning.novelty)) continue;
      final viewId = await repo.addBelongingView(belongingId: row.id, spaceId: spaceId, vector: v, source: 'turn');
      final view = BelongingView(viewId, v, 'turn');
      views.add(view);
      added.add(view);
    }
    final latest = _rows[id] ?? row;
    _rows[id] = latest.copyWith(views: [...latest.views, ...added]);
    _rematchScene();
  }

  void deleteBelonging(Belonging b) {
    final dbId = int.tryParse(b.id);
    if (onBoard && dbId != null) repo.deleteBelonging(dbId);
    _rows.remove(b.id);
    _questions.remove(b.id);
    _rejects.remove(b.id);
    if (activeQuestion?.belongingId == dbId) activeQuestion = null;
    belongings.remove(b);
    _devTray.remove(b.id);
    _presence.remove(b.id);
    _lastSeenBox.remove(b.id);
    _acks.removeWhere((k) => k.startsWith('${b.id}:'));
    _changed();
  }
}
