import 'dart:math';
import 'dart:typed_data';

import '../../core/data/models.dart';
import 'gallery_matcher.dart';
import 'observation.dart';

/// 확인 학습: 애매한 물건은 주인에게 묻고, "맞아요" 한 모습만 그 물건 사진으로 더한다.
class Learning {
  static const maxViews = 6; // 등록 1 + 확인 5
  static const maxTurns = 9;
  static const novelty = 0.85; // 이보다 비슷한 사진이 있으면 더하지 않는다
  static const rejectNear = 0.9; // "아니에요" 한 모습과 이만큼 비슷하면 다시 묻지 않는다

  static const questionTtl = Duration(hours: 36);
}

double cosine(Float32List a, Float32List b) => dot(normalized(a), normalized(b));

/// 너무 작거나 길쭉하거나, 가장자리에 얇게 걸친(트레이 밖 물건) 박스를 거른다.
bool plausibleBox(List<int> b, int imageW, int imageH) {
  final short = min(b[2], b[3]), long = max(b[2], b[3]);
  if (short < 40 || long > short * 8) return false;
  const edge = 20, thin = 80;
  final x = b[0], y = b[1], w = b[2], h = b[3];
  if ((y <= edge || y + h >= imageH - edge) && h < thin) return false;
  if ((x <= edge || x + w >= imageW - edge) && w < thin) return false;
  return true;
}

/// IoU > 0.6 이면 같은 박스로 본다 (관측마다 몇 px 씩 흔들린다).
bool sameBox(List<int> a, List<int> b) {
  final ix = max(0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]));
  final iy = max(0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]));
  final inter = ix * iy;
  return inter / (a[2] * a[3] + b[2] * b[3] - inter) > 0.6;
}

List<ObservedCandidate> drawableCandidates(BelongingObservation o) =>
    [for (final c in o.candidates) if (usableVector(c.embedding, o.dim) && plausibleBox(c.bbox, o.imageWidth, o.imageHeight)) c];

enum Band { confirmed, ask, unknown }

Band bandOf(CandidateMatch m) {
  if (m.decision == MatchDecision.matched) return Band.confirmed;
  if (m.bestItemId != null && m.best >= m.askFloor) return Band.ask;
  return Band.unknown;
}

bool nearReject(List<Float32List> rejects, Float32List v) => rejects.any((r) => cosine(r, v) >= Learning.rejectNear);

class ViewChange {
  final int? replaceViewId; // null 이면 그냥 더한다

  const ViewChange(this.replaceViewId);
}

/// null 이면 더하지 않는다.
ViewChange? planAddView(List<BelongingView> views, Float32List v) {
  if (views.any((w) => cosine(w.vector, v) >= Learning.novelty)) return null;
  if (views.where((w) => w.source != 'turn').length < Learning.maxViews) return const ViewChange(null);
  // 꽉 차면 다른 사진과 가장 겹치는 확인 사진을 바꾼다
  int? worst;
  var worstOverlap = -2.0;
  for (final w in views.where((w) => w.source == 'confirm')) {
    final overlap = views.where((o) => o.id != w.id).map((o) => cosine(o.vector, w.vector)).fold(-1.0, max);
    if (overlap > worstOverlap) {
      worstOverlap = overlap;
      worst = w.id;
    }
  }
  return worst == null ? null : ViewChange(worst);
}
