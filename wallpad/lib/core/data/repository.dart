import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../../features/auth/pin.dart';
import 'database.dart';
import 'models.dart';

abstract class Repository {
  Future<List<Member>> fetchMembers();

  /// [draft] = 온보딩 중인 임시 멤버. [finishDraftMember] 로 확정한다
  Future<Member> insertMember(String name, {bool draft = false});
  Future<void> finishDraftMember(int id);
  Future<int> deleteDraftMembers();
  Future<void> renameMember(int id, String name);
  Future<void> clearEmbeddings(int memberId);

  /// 없는 id 면 false
  Future<bool> deleteMember(int id);

  Future<List<Situation>> fetchSituations();
  Future<List<Item>> fetchItems();

  /// label 이 이미 있으면 null
  Future<Item?> insertItem({
    required String label,
    required String displayName,
  });

  Future<List<Item>> fetchChecklistItems({
    required int memberId,
    required int situationId,
  });

  Future<bool> deleteItem(int id);

  Future<Map<int, PinHash>> fetchPins();
  Future<void> savePin(int memberId, PinHash pin);

  /// 귀가 소지품 확인을 끈 사람들 (기본은 켜짐)
  Future<Set<int>> fetchReturnCheckOff();
  Future<void> saveReturnCheck(int memberId, bool on);

  /// pose 는 front · left · right. 같은 방향은 덮어쓴다
  Future<void> saveEmbedding({
    required int memberId,
    required String pose,
    required List<double> embedding,
  });

  Future<List<String>> fetchEmbeddingPoses(int memberId);

  Future<List<OwnedBelonging>> fetchBelongings();
  Future<void> updateBelonging(int id, {required String name, required List<int> memberIds});

  /// 첫 사진 특징의 출처가 [source] (register · redbox)
  Future<OwnedBelonging> insertBelonging({
    required List<int> memberIds,
    required String name,
    required String spaceId,
    required List<Float32List> vectors,
    Uint8List? thumbnail,
    bool hardToDetect = false,
    String source = 'register',
    List<int>? watchBox,
  });

  Future<void> setWatchBox(int id, List<int>? box);
  Future<bool> deleteBelonging(int id);
  Future<int> addBelongingView({required int belongingId, required String spaceId, required Float32List vector, required String source});
  Future<void> deleteBelongingView(int viewId);

  /// 물건마다 기다리는 질문은 하나. 있던 것은 이 모습으로 바꾼다
  Future<BelongingQuestion> putQuestion({
    required int belongingId,
    required String spaceId,
    required Float32List vector,
    Uint8List? crop,
    required double score,
    required DateTime seenAt,
  });

  Future<List<BelongingQuestion>> fetchPendingQuestions();
  Future<void> answerQuestion(int questionId, String status);
  Future<void> insertReject({required int belongingId, required String spaceId, required Float32List vector});
  Future<Map<int, List<Float32List>>> fetchRejects();

  Future<int> openPresence(int belongingId, DateTime from);
  Future<void> closePresence(int id, DateTime until, String closedBy, {int? takenBy});
  Future<void> closeOpenPresences(DateTime until, String closedBy);

  /// [since] 이후에 닫혔거나 아직 열린 구간. 물건별 seen_from 오름차순
  Future<Map<int, List<Presence>>> fetchPresence(DateTime since);
  Future<void> prunePresence(DateTime before);

  /// [at] 뒤의 구간 시각을 [at] 으로 당긴다
  Future<void> clampPresence(DateTime at);

  Future<void> insertMemberEvent(int memberId, String kind, DateTime at);

  /// 적은 순서로 마지막 귀가 (화면 시각을 옮겨 적었어도 가장 최근 것)
  Future<Map<int, DateTime>> fetchLastReturns();

  /// 마지막 사건이 departed 이고 그 날짜가 [day] 인 사람
  Future<Map<int, DateTime>> fetchOpenDepartures(String day);

  Future<void> putDayItem(int memberId, String day, String kind, String itemKey, {String? name, required DateTime at});
  Future<void> deleteDayItem(int memberId, String day, String kind, String itemKey);
  Future<void> deleteDayItems(int memberId, String day, String kind);
  Future<List<DayItem>> fetchDayItems(String sinceDay);
  Future<void> pruneDayItems(String beforeDay);

  /// 출발 · 귀가 기록, 하루 기록, [알고 있어요] 를 모두 지운다
  Future<void> resetDayState();
  Future<void> resetMembers();

  Future<void> setAck(int belongingId, int memberId, DateTime at);
  Future<void> deleteAck(int belongingId, int memberId);
  Future<void> deleteAcksOfMember(int memberId);
  Future<Map<int, Set<int>>> fetchAcks();

  Future<void> saveProfile(int memberId, MemberProfile p);
  Future<Map<int, MemberProfile>> fetchProfiles();

  // member_checks 표는 남아 있지만 지금은 쓰지 않는다
  Future<void> setEssentials(int memberId, List<String> names);
  Future<Map<int, List<String>>> fetchEssentials();

  /// 1등이 [threshold] 미만이거나 2등과의 차이가 [margin] 미만이면 null
  Future<Member?> findMemberByEmbedding(
    List<double> embedding, {
    double threshold = 0.363,
    double margin = 0,
  });

  /// 판정 없이 사람별 최고 유사도 (기준값 조정 로그용)
  Future<Map<int, double>> faceScores(List<double> embedding);
}

class SqliteRepository implements Repository {
  final AppDatabase _database;

  SqliteRepository(this._database);

  Database get _db => _database.db;

  @override
  Future<List<Member>> fetchMembers() async {
    final rows = _db.select('SELECT id, name FROM members ORDER BY id');
    return rows.map(Member.fromRow).toList();
  }

  @override
  Future<Member> insertMember(String name, {bool draft = false}) async {
    _db.execute('INSERT INTO members (name, onboarding) VALUES (?, ?)', [name, draft ? 1 : 0]);
    final rows = _db.select(
      'SELECT id, name FROM members WHERE id = ?',
      [_db.lastInsertRowId],
    );
    return Member.fromRow(rows.first);
  }

  @override
  Future<void> finishDraftMember(int id) async {
    _db.execute('UPDATE members SET onboarding = 0 WHERE id = ?', [id]);
  }

  @override
  Future<int> deleteDraftMembers() async {
    _db.execute('DELETE FROM members WHERE onboarding = 1');
    return _db.updatedRows;
  }

  @override
  Future<void> renameMember(int id, String name) async {
    _db.execute('UPDATE members SET name = ? WHERE id = ?', [name, id]);
  }

  @override
  Future<void> clearEmbeddings(int memberId) async {
    _db.execute('DELETE FROM face_embeddings WHERE member_id = ?', [memberId]);
  }

  @override
  Future<bool> deleteMember(int id) async {
    _db.execute('DELETE FROM members WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  @override
  Future<Map<int, PinHash>> fetchPins() async {
    final rows = _db.select('SELECT id, pin_hash, pin_salt FROM members WHERE pin_hash IS NOT NULL AND pin_salt IS NOT NULL');
    return {for (final r in rows) r['id'] as int: PinHash(r['pin_hash'] as String, r['pin_salt'] as String)};
  }

  @override
  Future<void> savePin(int memberId, PinHash pin) async {
    _db.execute('UPDATE members SET pin_hash = ?, pin_salt = ? WHERE id = ?', [pin.hash, pin.salt, memberId]);
  }

  @override
  Future<Set<int>> fetchReturnCheckOff() async {
    final rows = _db.select('SELECT id FROM members WHERE return_check = 0');
    return {for (final r in rows) r['id'] as int};
  }

  @override
  Future<void> saveReturnCheck(int memberId, bool on) async {
    _db.execute('UPDATE members SET return_check = ? WHERE id = ?', [on ? 1 : 0, memberId]);
  }

  @override
  Future<bool> deleteItem(int id) async {
    _db.execute('DELETE FROM items WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  @override
  Future<List<Situation>> fetchSituations() async {
    final rows = _db.select('SELECT id, name FROM situation ORDER BY id');
    return rows.map(Situation.fromRow).toList();
  }

  @override
  Future<List<Item>> fetchItems() async {
    final rows = _db.select(
      'SELECT id, label, display_name FROM items ORDER BY id',
    );
    return rows.map(Item.fromRow).toList();
  }

  @override
  Future<Item?> insertItem({
    required String label,
    required String displayName,
  }) async {
    final existing = _db.select('SELECT id FROM items WHERE label = ?', [label]);
    if (existing.isNotEmpty) return null;

    _db.execute(
      'INSERT INTO items (label, display_name) VALUES (?, ?)',
      [label, displayName],
    );
    final rows = _db.select(
      'SELECT id, label, display_name FROM items WHERE id = ?',
      [_db.lastInsertRowId],
    );
    return Item.fromRow(rows.first);
  }

  @override
  Future<List<Item>> fetchChecklistItems({
    required int memberId,
    required int situationId,
  }) async {
    final rows = _db.select(
      '''
      SELECT i.id, i.label, i.display_name
      FROM member_checklist_items c
      JOIN items i ON i.id = c.item_id
      WHERE c.member_id = ? AND c.situation_id = ?
      ORDER BY i.display_name
      ''',
      [memberId, situationId],
    );
    return rows.map(Item.fromRow).toList();
  }

  static const _poses = ['front', 'left', 'right'];

  // 단위벡터로 만들어 두면 내적이 곧 코사인 유사도다
  static Float32List _normalize(List<double> v) {
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = norm == 0 ? 1 : sqrt(norm);
    return Float32List.fromList([for (final x in v) x / norm]);
  }

  static Float32List _average(List<Float32List> vectors) {
    final sum = List<double>.filled(vectors.first.length, 0);
    for (final v in vectors) {
      for (var i = 0; i < sum.length && i < v.length; i++) {
        sum[i] += v[i];
      }
    }
    return _normalize(sum);
  }

  static double _similarity(Float32List a, Float32List b) {
    var dot = 0.0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  @override
  Future<void> saveEmbedding({
    required int memberId,
    required String pose,
    required List<double> embedding,
  }) async {
    if (!_poses.contains(pose)) throw ArgumentError('pose 는 front/left/right 중 하나');
    if (embedding.isEmpty) throw ArgumentError('embedding 이 비어 있음');
    final bytes = _normalize(embedding).buffer.asUint8List();
    _db.execute('INSERT OR IGNORE INTO face_embeddings (member_id) VALUES (?)', [memberId]);
    _db.execute('UPDATE face_embeddings SET $pose = ? WHERE member_id = ?', [bytes, memberId]);
  }

  @override
  Future<List<String>> fetchEmbeddingPoses(int memberId) async {
    final rows = _db.select(
      'SELECT front, left, right FROM face_embeddings WHERE member_id = ?',
      [memberId],
    );
    if (rows.isEmpty) return [];
    return _poses.where((p) => rows.first[p] != null).toList();
  }

  // 복사해서 정렬 문제를 피한다
  static Float32List _f32(Uint8List blob) => Uint8List.fromList(blob).buffer.asFloat32List();

  static Uint8List _bytes(Float32List v) => Uint8List.fromList(v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes));

  @override
  Future<List<OwnedBelonging>> fetchBelongings() async {
    final views = <int, List<BelongingView>>{};
    final spaces = <int, String>{};
    for (final row in _db.select('SELECT id, belonging_id, space_id, vector, source FROM belonging_views ORDER BY id')) {
      final id = row['belonging_id'] as int;
      views.putIfAbsent(id, () => []).add(BelongingView(row['id'] as int, _f32(row['vector'] as Uint8List), row['source'] as String));
      spaces[id] = row['space_id'] as String;
    }
    final owners = <int, List<int>>{};
    for (final row in _db.select('SELECT belonging_id, member_id FROM belonging_owners ORDER BY rowid')) {
      owners.putIfAbsent(row['belonging_id'] as int, () => []).add(row['member_id'] as int);
    }
    return [
      for (final row in _db.select('SELECT id, member_id, name, thumbnail, hard_to_detect, watch_box FROM belongings ORDER BY id'))
        OwnedBelonging(row['id'] as int, owners[row['id']] ?? [row['member_id'] as int], row['name'] as String, spaces[row['id']], views[row['id']] ?? const [],
            thumbnail: row['thumbnail'] as Uint8List?, hardToDetect: (row['hard_to_detect'] as int) != 0, watchBox: _box(row['watch_box'] as String?)),
    ];
  }

  @override
  Future<void> updateBelonging(int id, {required String name, required List<int> memberIds}) async {
    if (memberIds.isEmpty) throw ArgumentError('주인이 없음');
    _db.execute('BEGIN');
    try {
      _db.execute('UPDATE belongings SET name = ?, member_id = ? WHERE id = ?', [name, memberIds.first, id]);
      _db.execute('DELETE FROM belonging_owners WHERE belonging_id = ?', [id]);
      for (final m in memberIds) {
        _db.execute('INSERT OR IGNORE INTO belonging_owners (belonging_id, member_id) VALUES (?, ?)', [id, m]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<OwnedBelonging> insertBelonging({
    required List<int> memberIds,
    required String name,
    required String spaceId,
    required List<Float32List> vectors,
    Uint8List? thumbnail,
    bool hardToDetect = false,
    String source = 'register',
    List<int>? watchBox,
  }) async {
    if (vectors.isEmpty) throw ArgumentError('등록 사진 특징이 없음');
    if (memberIds.isEmpty) throw ArgumentError('주인이 없음');
    _db.execute('BEGIN');
    try {
      _db.execute('INSERT INTO belongings (member_id, name, thumbnail, hard_to_detect, watch_box) VALUES (?, ?, ?, ?, ?)',
          [memberIds.first, name, thumbnail, hardToDetect ? 1 : 0, watchBox?.join(',')]);
      final id = _db.lastInsertRowId;
      for (final m in memberIds) {
        _db.execute('INSERT OR IGNORE INTO belonging_owners (belonging_id, member_id) VALUES (?, ?)', [id, m]);
      }
      final views = <BelongingView>[];
      for (final (i, v) in vectors.indexed) {
        final s = i == 0 ? source : 'register';
        _db.execute('INSERT INTO belonging_views (belonging_id, space_id, vector, source) VALUES (?, ?, ?, ?)', [id, spaceId, _bytes(v), s]);
        views.add(BelongingView(_db.lastInsertRowId, v, s));
      }
      _db.execute('COMMIT');
      return OwnedBelonging(id, memberIds, name, spaceId, views, thumbnail: thumbnail, hardToDetect: hardToDetect, watchBox: watchBox);
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> setWatchBox(int id, List<int>? box) async {
    _db.execute('UPDATE belongings SET watch_box = ? WHERE id = ?', [box?.join(','), id]);
  }

  static List<int>? _box(String? s) {
    final p = s?.split(',').map(int.tryParse).toList();
    return p == null || p.length != 4 || p.contains(null) ? null : p.cast<int>();
  }

  @override
  Future<bool> deleteBelonging(int id) async {
    _db.execute('DELETE FROM belongings WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  @override
  Future<int> addBelongingView({required int belongingId, required String spaceId, required Float32List vector, required String source}) async {
    _db.execute('INSERT INTO belonging_views (belonging_id, space_id, vector, source) VALUES (?, ?, ?, ?)',
        [belongingId, spaceId, _bytes(vector), source]);
    return _db.lastInsertRowId;
  }

  @override
  Future<void> deleteBelongingView(int viewId) async {
    _db.execute('DELETE FROM belonging_views WHERE id = ?', [viewId]);
  }

  @override
  Future<BelongingQuestion> putQuestion({
    required int belongingId,
    required String spaceId,
    required Float32List vector,
    Uint8List? crop,
    required double score,
    required DateTime seenAt,
  }) async {
    _db.execute('BEGIN');
    try {
      _db.execute("DELETE FROM belonging_questions WHERE belonging_id = ? AND status = 'pending'", [belongingId]);
      _db.execute('INSERT INTO belonging_questions (belonging_id, space_id, vector, crop, score, seen_at) VALUES (?, ?, ?, ?, ?, ?)',
          [belongingId, spaceId, _bytes(vector), crop, score, seenAt.toIso8601String()]);
      final id = _db.lastInsertRowId;
      _db.execute('COMMIT');
      return BelongingQuestion(id, belongingId, spaceId, vector, crop, score, seenAt);
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<List<BelongingQuestion>> fetchPendingQuestions() async => [
        for (final r in _db.select(
            "SELECT id, belonging_id, space_id, vector, crop, score, seen_at FROM belonging_questions WHERE status = 'pending' ORDER BY id"))
          BelongingQuestion(r['id'] as int, r['belonging_id'] as int, r['space_id'] as String, _f32(r['vector'] as Uint8List),
              r['crop'] as Uint8List?, (r['score'] as num).toDouble(), DateTime.parse(r['seen_at'] as String)),
      ];

  @override
  Future<void> answerQuestion(int questionId, String status) async {
    _db.execute("UPDATE belonging_questions SET status = ?, answered_at = datetime('now') WHERE id = ?", [status, questionId]);
  }

  @override
  Future<void> insertReject({required int belongingId, required String spaceId, required Float32List vector}) async {
    _db.execute('INSERT INTO belonging_rejects (belonging_id, space_id, vector) VALUES (?, ?, ?)', [belongingId, spaceId, _bytes(vector)]);
  }

  @override
  Future<Map<int, List<Float32List>>> fetchRejects() async {
    final out = <int, List<Float32List>>{};
    for (final r in _db.select('SELECT belonging_id, vector FROM belonging_rejects ORDER BY id')) {
      out.putIfAbsent(r['belonging_id'] as int, () => []).add(_f32(r['vector'] as Uint8List));
    }
    return out;
  }

  @override
  Future<int> openPresence(int belongingId, DateTime from) async {
    _db.execute('INSERT INTO belonging_presence (belonging_id, seen_from) VALUES (?, ?)', [belongingId, from.toIso8601String()]);
    return _db.lastInsertRowId;
  }

  @override
  Future<void> closePresence(int id, DateTime until, String closedBy, {int? takenBy}) async {
    _db.execute('UPDATE belonging_presence SET seen_until = ?, closed_by = ?, taken_by = ? WHERE id = ? AND seen_until IS NULL',
        [until.toIso8601String(), closedBy, takenBy, id]);
  }

  @override
  Future<void> closeOpenPresences(DateTime until, String closedBy) async {
    _db.execute('UPDATE belonging_presence SET seen_until = ?, closed_by = ? WHERE seen_until IS NULL', [until.toIso8601String(), closedBy]);
  }

  @override
  Future<Map<int, List<Presence>>> fetchPresence(DateTime since) async {
    final out = <int, List<Presence>>{};
    for (final r in _db.select(
        'SELECT id, belonging_id, seen_from, seen_until, closed_by, taken_by FROM belonging_presence WHERE seen_until IS NULL OR seen_until >= ? ORDER BY seen_from',
        [since.toIso8601String()])) {
      final until = r['seen_until'] as String?;
      out.putIfAbsent(r['belonging_id'] as int, () => []).add(Presence(r['id'] as int, r['belonging_id'] as int, DateTime.parse(r['seen_from'] as String),
          until == null ? null : DateTime.parse(until), r['closed_by'] as String?, takenBy: r['taken_by'] as int?));
    }
    return out;
  }

  @override
  Future<void> prunePresence(DateTime before) async {
    _db.execute('DELETE FROM belonging_presence WHERE seen_until IS NOT NULL AND seen_until < ?', [before.toIso8601String()]);
  }

  @override
  Future<void> clampPresence(DateTime at) async {
    final t = at.toIso8601String();
    _db.execute('UPDATE belonging_presence SET seen_from = ? WHERE seen_from > ?', [t, t]);
    _db.execute('UPDATE belonging_presence SET seen_until = ? WHERE seen_until > ?', [t, t]);
  }

  @override
  Future<void> insertMemberEvent(int memberId, String kind, DateTime at) async {
    _db.execute('INSERT INTO member_events (member_id, kind, at) VALUES (?, ?, ?)', [memberId, kind, at.toIso8601String()]);
  }

  @override
  Future<Map<int, DateTime>> fetchLastReturns() async => {
        for (final r in _db.select('''
          SELECT e.member_id, e.at FROM member_events e
          WHERE e.id = (SELECT MAX(id) FROM member_events WHERE member_id = e.member_id AND kind = 'returned')'''))
          r['member_id'] as int: DateTime.parse(r['at'] as String),
      };

  @override
  Future<Map<int, DateTime>> fetchOpenDepartures(String day) async => {
        for (final r in _db.select('''
          SELECT e.member_id, e.kind, e.at FROM member_events e
          WHERE e.id = (SELECT MAX(id) FROM member_events WHERE member_id = e.member_id)'''))
          if (r['kind'] == 'departed' && (r['at'] as String).startsWith(day)) r['member_id'] as int: DateTime.parse(r['at'] as String),
      };

  @override
  Future<void> putDayItem(int memberId, String day, String kind, String itemKey, {String? name, required DateTime at}) async {
    _db.execute('INSERT OR REPLACE INTO member_day_items (member_id, day, kind, item_key, name, at) VALUES (?, ?, ?, ?, ?, ?)',
        [memberId, day, kind, itemKey, name, at.toIso8601String()]);
  }

  @override
  Future<void> deleteDayItem(int memberId, String day, String kind, String itemKey) async {
    _db.execute('DELETE FROM member_day_items WHERE member_id = ? AND day = ? AND kind = ? AND item_key = ?', [memberId, day, kind, itemKey]);
  }

  @override
  Future<void> deleteDayItems(int memberId, String day, String kind) async {
    _db.execute('DELETE FROM member_day_items WHERE member_id = ? AND day = ? AND kind = ?', [memberId, day, kind]);
  }

  @override
  Future<List<DayItem>> fetchDayItems(String sinceDay) async => [
        for (final r in _db.select('SELECT member_id, day, kind, item_key, name, at FROM member_day_items WHERE day >= ? ORDER BY at', [sinceDay]))
          DayItem(r['member_id'] as int, r['day'] as String, r['kind'] as String, r['item_key'] as String, r['name'] as String?, DateTime.parse(r['at'] as String)),
      ];

  @override
  Future<void> pruneDayItems(String beforeDay) async {
    _db.execute('DELETE FROM member_day_items WHERE day < ?', [beforeDay]);
  }

  @override
  Future<void> resetDayState() async {
    _db.execute('DELETE FROM member_events');
    _db.execute('DELETE FROM member_day_items');
    _db.execute('DELETE FROM belonging_acks');
  }

  @override
  Future<void> resetMembers() async {
    for (final t in ['belongings', 'members', 'member_events', 'member_day_items', 'belonging_acks', 'member_checks']) {
      _db.execute('DELETE FROM $t');
    }
  }

  @override
  Future<void> setAck(int belongingId, int memberId, DateTime at) async {
    _db.execute('INSERT OR REPLACE INTO belonging_acks (belonging_id, member_id, at) VALUES (?, ?, ?)', [belongingId, memberId, at.toIso8601String()]);
  }

  @override
  Future<void> deleteAck(int belongingId, int memberId) async {
    _db.execute('DELETE FROM belonging_acks WHERE belonging_id = ? AND member_id = ?', [belongingId, memberId]);
  }

  @override
  Future<void> deleteAcksOfMember(int memberId) async {
    _db.execute('DELETE FROM belonging_acks WHERE member_id = ?', [memberId]);
  }

  @override
  Future<Map<int, Set<int>>> fetchAcks() async {
    final out = <int, Set<int>>{};
    for (final r in _db.select('SELECT belonging_id, member_id FROM belonging_acks')) {
      out.putIfAbsent(r['belonging_id'] as int, () => {}).add(r['member_id'] as int);
    }
    return out;
  }

  @override
  Future<void> saveProfile(int memberId, MemberProfile p) async {
    _db.execute(
        'INSERT OR REPLACE INTO member_profile (member_id, weekday_place, schedule_mode, leave_time, return_time, days, remind_before, transport, weekend, updated_at) '
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))",
        [memberId, p.weekdayPlace, p.scheduleMode, p.leaveTime, p.returnTime, p.days, p.remindBefore, p.transport, p.weekend]);
  }

  @override
  Future<Map<int, MemberProfile>> fetchProfiles() async => {
        for (final r in _db.select('SELECT * FROM member_profile')) r['member_id'] as int: MemberProfile.fromRow(r),
      };

  void _setNames(String table, int memberId, List<String> names) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM $table WHERE member_id = ?', [memberId]);
      for (final n in names) {
        _db.execute('INSERT OR IGNORE INTO $table (member_id, name) VALUES (?, ?)', [memberId, n]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<int, List<String>> _names(String table) {
    final out = <int, List<String>>{};
    for (final r in _db.select('SELECT member_id, name FROM $table ORDER BY rowid')) {
      out.putIfAbsent(r['member_id'] as int, () => []).add(r['name'] as String);
    }
    return out;
  }

  @override
  Future<void> setEssentials(int memberId, List<String> names) async => _setNames('member_essentials', memberId, names);

  @override
  Future<Map<int, List<String>>> fetchEssentials() async => _names('member_essentials');

  @override
  Future<Map<int, double>> faceScores(List<double> embedding) async => _bestScores(_normalize(embedding));

  @override
  Future<Member?> findMemberByEmbedding(
    List<double> embedding, {
    double threshold = 0.363,
    double margin = 0,
  }) async {
    final best = _bestScores(_normalize(embedding));
    if (best.isEmpty) return null;

    final ranked = best.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.first.value < threshold) return null;
    if (ranked.length > 1 && ranked.first.value - ranked[1].value < margin) return null;

    final found = _db.select('SELECT id, name FROM members WHERE id = ?', [ranked.first.key]);
    return found.isEmpty ? null : Member.fromRow(found.first);
  }

  Map<int, double> _bestScores(Float32List query) {
    final best = <int, double>{};
    for (final row in _db.select('SELECT member_id, front, left, right FROM face_embeddings')) {
      final id = row['member_id'] as int;
      final stored = <Float32List>[];
      for (final pose in _poses) {
        final blob = row[pose];
        if (blob != null) stored.add(_f32(blob as Uint8List));
      }
      if (stored.isEmpty) continue;

      // 평균 벡터는 한 방향이 우연히 닮은 것에 덜 흔들린다
      for (final template in [...stored, _average(stored)]) {
        final score = _similarity(template, query);
        if (score > (best[id] ?? -1)) best[id] = score;
      }
    }
    return best;
  }
}
