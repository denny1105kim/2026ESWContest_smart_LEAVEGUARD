import 'dart:math';
import 'dart:typed_data';

import 'observation.dart';

/// 소지품 하나의 등록 사진 특징 (정규화해 둔다).
class ItemViews {
  final String itemId;
  final List<Float32List> vectors;

  ItemViews(this.itemId, List<Float32List> raw) : vectors = [for (final v in raw) normalized(v)];
}

Float32List normalized(Float32List v) {
  var s = 0.0;
  for (final x in v) {
    s += x * x;
  }
  final n = max(sqrt(s), 1e-12);
  return Float32List.fromList([for (final x in v) x / n]);
}

double dot(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length && i < b.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

enum MatchDecision {
  matched,
  unknown,
  ambiguous, // 1·2위가 너무 가깝다
}

class CandidateMatch {
  final int candidateId;
  final List<int> bbox;
  final MatchDecision decision;
  final String? itemId;
  final double best;
  final String? bestItemId;
  final double askFloor; // 이 점수 이상이면 확인 질문

  const CandidateMatch(this.candidateId, this.bbox, this.decision, this.itemId, this.best, this.bestItemId, {this.askFloor = MatchRule.legacyAskFloor});
}

/// 특징 공간별 기준값. 공간 ID 에 '+' 가 있으면 두 모델을 이어 붙인 특징이다.
class MatchRule {
  final double threshold, margin, askFloor;

  const MatchRule(this.threshold, this.margin, this.askFloor);

  static const legacyAskFloor = 0.42;
  static const legacy = MatchRule(0.45, 0.08, legacyAskFloor);
  static const fused = MatchRule(0.56, 0.08, 0.47);

  static MatchRule forSpace(String spaceId) => spaceId.contains('+') ? fused : legacy;
}

/// 후보를 가족 전체 소지품과 맞춘다. 물건 점수는 등록 사진들과의 코사인 최댓값이다.
class GalleryMatcher {
  final List<ItemViews> gallery;
  final double threshold;
  final double margin;
  final double askFloor;

  GalleryMatcher(this.gallery, {double? threshold, double? margin, double? askFloor})
      : threshold = threshold ?? MatchRule.legacy.threshold,
        margin = margin ?? MatchRule.legacy.margin,
        askFloor = askFloor ?? MatchRule.legacy.askFloor;

  factory GalleryMatcher.forSpace(List<ItemViews> gallery, String spaceId) {
    final r = MatchRule.forSpace(spaceId);
    return GalleryMatcher(gallery, threshold: r.threshold, margin: r.margin, askFloor: r.askFloor);
  }

  List<CandidateMatch> match(List<ObservedCandidate> candidates) {
    final queries = [for (final c in candidates) normalized(c.embedding!)];
    final scores = [
      for (final q in queries)
        {
          for (final item in gallery) item.itemId: item.vectors.map((v) => dot(q, v)).fold(-1.0, max),
        },
    ];

    // 점수 높은 짝부터 1:1 배정
    final pairs = [
      for (var i = 0; i < candidates.length; i++)
        for (final e in scores[i].entries) (c: i, item: e.key, score: e.value),
    ]..sort((a, b) => b.score.compareTo(a.score));
    final taken = <String>{};
    final assigned = <int, String>{};
    final ambiguous = <int>{};
    for (final p in pairs) {
      if (p.score < threshold) break;
      if (assigned.containsKey(p.c) || ambiguous.contains(p.c) || taken.contains(p.item)) continue;
      if (p.score - _secondOther(scores[p.c], p.item) < margin) {
        ambiguous.add(p.c);
        continue;
      }
      assigned[p.c] = p.item;
      taken.add(p.item);
    }

    return [
      for (var i = 0; i < candidates.length; i++) _result(candidates[i], scores[i], assigned[i], ambiguous.contains(i)),
    ];
  }

  CandidateMatch _result(ObservedCandidate c, Map<String, double> s, String? item, bool amb) {
    String? bestId;
    var best = -1.0;
    for (final e in s.entries) {
      if (e.value > best) {
        best = e.value;
        bestId = e.key;
      }
    }
    final decision = item != null ? MatchDecision.matched : (amb ? MatchDecision.ambiguous : MatchDecision.unknown);
    return CandidateMatch(c.id, c.bbox, decision, item, best, bestId, askFloor: askFloor);
  }

  static double _secondOther(Map<String, double> s, String item) {
    var second = -1.0;
    for (final e in s.entries) {
      if (e.key != item && e.value > second) second = e.value;
    }
    return second;
  }
}
