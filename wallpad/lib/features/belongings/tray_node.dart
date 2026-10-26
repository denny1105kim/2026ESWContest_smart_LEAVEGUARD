import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/config/scan_config.dart';
import 'observation.dart';

class BoxEncoding {
  final int frameId;
  final List<int> bbox;
  final String spaceId;
  final int dim;
  final Float32List vector;

  const BoxEncoding(this.frameId, this.bbox, this.spaceId, this.dim, this.vector);
}

/// 트레이 노드 HTTP. 관측의 frame_id 로 사진·박스 특징을 받는다 (노드는 최근 16장만 남긴다).
class TrayNode {
  final String base;

  TrayNode([this.base = TrayNodeConfig.url]);

  String get rawStream => '$base/raw.mjpeg';

  static String _box(List<int> b) => 'x=${b[0]}&y=${b[1]}&w=${b[2]}&h=${b[3]}';

  Future<Uint8List?> snapshot(int frameId) => _get('/snapshot.jpg?frame_id=$frameId');

  Future<Uint8List?> crop(int frameId, List<int> bbox) => _get('/crop.jpg?frame_id=$frameId&${_box(bbox)}');

  /// [save] 면 노드가 재학습용으로 남긴다.
  Future<BoxEncoding?> encode(int frameId, List<int> bbox, {bool save = false, int? rot}) async {
    final body = await _send('POST', '/encode?frame_id=$frameId&${_box(bbox)}${save ? '&save=1' : ''}${rot != null ? '&rot=$rot' : ''}');
    if (body == null) return null;
    try {
      final j = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      final dim = j['embedding_dim'] as int;
      final v = decodeF32(j['embedding'] as String);
      if (!usableVector(v, dim)) return null;
      return BoxEncoding(j['frame_id'] as int, (j['bbox'] as List).cast<int>(), j['embedding_space_id'] as String, dim, v);
    } catch (_) {
      return null;
    }
  }

  Future<List<Float32List>> turns(int frameId, List<int> bbox) async => [
        for (final rot in const [90, 180, 270])
          if (await encode(frameId, bbox, rot: rot) case final e?) e.vector,
      ];

  Future<Uint8List?> _get(String path) => _send('GET', path);

  Future<Uint8List?> _send(String method, String path) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.openUrl(method, Uri.parse('$base$path'));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final bytes = await res.fold<BytesBuilder>(BytesBuilder(copy: false), (b, c) => b..add(c)).timeout(const Duration(seconds: 8));
      return res.statusCode == 200 ? bytes.takeBytes() : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// state 는 moving · settling · stable.
  Future<({String state, int sequence})?> health() async {
    final body = await _get('/health');
    if (body == null) return null;
    try {
      final j = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      return (state: j['state'] as String? ?? '', sequence: j['sequence'] as int? ?? 0);
    } catch (_) {
      return null;
    }
  }
}
