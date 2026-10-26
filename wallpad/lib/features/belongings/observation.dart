import 'dart:convert';
import 'dart:typed_data';

/// 트레이 노드 관측 한 건 (schema 1·2). 어떤 물건인지는 월패드가 정한다.
class BelongingObservation {
  final String deviceId;
  final String bootId;
  final int sequence;
  final String observationId;
  final String? requestId;
  final int frameAgeMs;
  final int imageWidth, imageHeight;
  final String spaceId;
  final int dim;
  final int? frameId; // schema 1 이면 null
  final bool l2Normalized;
  final bool sceneValid;
  final String? invalidReason;
  final bool moving;
  final List<ObservedCandidate> candidates;

  const BelongingObservation({
    required this.deviceId,
    required this.bootId,
    required this.sequence,
    required this.observationId,
    required this.requestId,
    required this.frameAgeMs,
    required this.imageWidth,
    required this.imageHeight,
    required this.spaceId,
    required this.dim,
    required this.frameId,
    required this.l2Normalized,
    required this.sceneValid,
    required this.invalidReason,
    required this.moving,
    required this.candidates,
  });

  BelongingObservation withCandidates(List<ObservedCandidate> extra) => BelongingObservation(
        deviceId: deviceId,
        bootId: bootId,
        sequence: sequence,
        observationId: observationId,
        requestId: requestId,
        frameAgeMs: frameAgeMs,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        spaceId: spaceId,
        dim: dim,
        frameId: frameId,
        l2Normalized: l2Normalized,
        sceneValid: sceneValid,
        invalidReason: invalidReason,
        moving: moving,
        candidates: [...candidates, ...extra],
      );

  factory BelongingObservation.parse(String text) {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) throw const FormatException('관측이 객체가 아님');
    final schema = j['schema_version'];
    if (schema != 1 && schema != 2) throw FormatException('모르는 schema_version: $schema');
    if (j['dtype'] != 'f32le') throw FormatException('모르는 dtype: ${j['dtype']}');
    final q = j['scene_quality'] as Map<String, dynamic>;
    return BelongingObservation(
      deviceId: j['device_id'] as String,
      bootId: j['boot_id'] as String,
      sequence: j['sequence'] as int,
      observationId: j['observation_id'] as String,
      requestId: j['request_id'] as String?,
      frameAgeMs: j['frame_age_ms_at_send'] as int,
      imageWidth: j['image_width'] as int,
      imageHeight: j['image_height'] as int,
      spaceId: j['embedding_space_id'] as String,
      dim: j['embedding_dim'] as int,
      frameId: j['frame_id'] as int?,
      l2Normalized: j['l2_normalized'] as bool? ?? true, // schema 1 은 늘 정규화해서 보냈다
      sceneValid: q['valid'] as bool,
      invalidReason: q['reason'] as String?,
      moving: q['moving'] as bool? ?? false,
      candidates: [
        for (final c in (j['candidates'] as List).cast<Map<String, dynamic>>())
          ObservedCandidate(
            id: c['id'] as int,
            bbox: (c['bbox'] as List).cast<int>(),
            embedding: c['embedding'] == null ? null : decodeF32(c['embedding'] as String),
          ),
      ],
    );
  }
}

class ObservedCandidate {
  final int id;
  final List<int> bbox; // 원본 픽셀 [x, y, w, h]
  final Float32List? embedding; // 인코딩 실패면 null

  const ObservedCandidate({required this.id, required this.bbox, required this.embedding});
}

Float32List decodeF32(String b64) {
  final bytes = base64Decode(b64);
  if (bytes.lengthInBytes % 4 != 0) throw const FormatException('벡터 길이가 4의 배수가 아님');
  return Float32List.view(Uint8List.fromList(bytes).buffer, 0, bytes.lengthInBytes ~/ 4);
}

bool usableVector(Float32List? v, int dim) {
  if (v == null || v.length != dim) return false;
  var sq = 0.0;
  for (final x in v) {
    if (x.isNaN || x.isInfinite) return false;
    sq += x * x;
  }
  return sq > 1e-6;
}
