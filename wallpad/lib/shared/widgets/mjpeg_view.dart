import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/wallpad_tokens.dart';

/// HTTP MJPEG 뷰어. 경계 문자열 대신 JPEG SOI/EOI 표시로 자른다.
class MjpegView extends StatefulWidget {
  final String url;

  const MjpegView({super.key, required this.url});

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  HttpClient? _client;
  StreamSubscription<List<int>>? _sub;
  Timer? _retry;
  Uint8List? _frame;
  String? _error;
  var _buffer = BytesBuilder(copy: false);
  var _disposed = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    final client = _client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final response = await (await client.getUrl(Uri.parse(widget.url))).close();
      if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
      _buffer = BytesBuilder(copy: false);
      _sub = response.listen(_onData, onError: (_) => _reconnect('영상이 끊겼어요'), onDone: () => _reconnect('영상이 끊겼어요'));
    } catch (_) {
      _reconnect('트레이 카메라에 연결할 수 없어요');
    }
  }

  void _onData(List<int> chunk) {
    _buffer.add(chunk);
    final bytes = _buffer.toBytes();
    Uint8List? latest;
    var rest = 0;
    // 밀리면 마지막 완성 장만 쓴다
    for (var start = _find(bytes, 0xD8, 0); start >= 0; start = _find(bytes, 0xD8, rest)) {
      final end = _find(bytes, 0xD9, start + 2);
      if (end < 0) break;
      latest = Uint8List.sublistView(bytes, start, end + 2);
      rest = end + 2;
    }
    _buffer = BytesBuilder(copy: false)..add(Uint8List.sublistView(bytes, rest));
    if (latest != null && mounted) {
      setState(() {
        _frame = Uint8List.fromList(latest!);
        _error = null;
      });
    }
  }

  static int _find(Uint8List b, int marker, int from) {
    for (var i = from; i + 1 < b.length; i++) {
      if (b[i] == 0xFF && b[i + 1] == marker) return i;
    }
    return -1;
  }

  void _reconnect(String why) {
    _sub?.cancel();
    _sub = null;
    _client?.close(force: true);
    _client = null;
    if (_disposed) return;
    if (mounted) setState(() => _error = why);
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), _connect);
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _sub?.cancel();
    _client?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (frame != null) Image.memory(frame, fit: BoxFit.contain, gaplessPlayback: true),
          if (frame == null || _error != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_error == null ? Icons.videocam_rounded : Icons.videocam_off_rounded, size: 64, color: Colors.white70),
                  const SizedBox(height: 16),
                  Text(_error ?? '트레이 카메라 연결 중…', style: const TextStyle(fontSize: 26, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(widget.url, style: TextStyle(fontSize: 18, color: Colors.white.withValues(alpha: 0.6))),
                ],
              ),
            ),
          if (frame != null && _error != null)
            Positioned(
              left: 16,
              top: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: WallpadTokens.danger, borderRadius: BorderRadius.circular(10)),
                child: Text(_error!, style: const TextStyle(fontSize: 20, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}
