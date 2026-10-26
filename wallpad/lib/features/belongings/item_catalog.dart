import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'learning.dart' show cosine;

/// 등록 화면의 종류 이름 제안. 종류별 대표 벡터와 비교하고, 특징 공간이 다르면 제안하지 않는다.
class ItemCatalog {
  ItemCatalog._(this.spaceId, this._protos, [this.minScore = 0.33]);

  final String spaceId;
  final List<_Proto> _protos;
  final double minScore; // 모델마다 점수 크기가 달라 파일에 둔다

  static Future<ItemCatalog>? _loading;

  /// 파일이 없거나 깨졌으면 빈 카탈로그.
  static Future<ItemCatalog> load() => _loading ??= _load();

  static Future<ItemCatalog> _load() async {
    try {
      final j = jsonDecode(await rootBundle.loadString('assets/item_catalog.json')) as Map<String, dynamic>;
      final protos = [
        for (final p in (j['prototypes'] as List).cast<Map<String, dynamic>>())
          _Proto(p['name'] as String, p['icon'] as String, Float32List.fromList((p['v'] as List).cast<num>().map((x) => x.toDouble()).toList())),
      ];
      return ItemCatalog._(j['space_id'] as String, protos, (j['min_score'] as num?)?.toDouble() ?? 0.33);
    } catch (_) {
      return ItemCatalog._('', const []);
    }
  }

  /// 가까운 순 상위 [count] 개. 1위도 [minScore] 아래면 빈 목록.
  List<ItemSuggestion> suggest(String? spaceId, Float32List? vector, {int count = 3, double? minScore}) {
    minScore ??= this.minScore;
    if (vector == null || spaceId != this.spaceId || _protos.isEmpty) return const [];
    final best = <String, ItemSuggestion>{};
    for (final p in _protos) {
      if (p.vector.length != vector.length) return const [];
      final s = cosine(p.vector, vector);
      if (s > (best[p.name]?.score ?? -1)) best[p.name] = ItemSuggestion(p.name, p.icon, s);
    }
    final ranked = best.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    if (ranked.isEmpty || ranked.first.score < minScore) return const [];
    return ranked.take(count).toList();
  }
}

class ItemSuggestion {
  const ItemSuggestion(this.name, this.icon, this.score);

  final String name;
  final String icon;
  final double score;
}

class _Proto {
  const _Proto(this.name, this.icon, this.vector);

  final String name;
  final String icon;
  final Float32List vector;
}
