import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/config/constants.dart';

class DoorFrame {
  final String device;

  final String mode; // idle | detected | known | unknown
  final int seq;
  final Uint8List jpeg;
  final DateTime at;

  const DoorFrame(this.device, this.mode, this.seq, this.jpeg, this.at);
}

/// ESP32-CAM 이 프레임을 올리는 HTTP 서버.
///   POST /api/camera/frames   JPEG 본문, 헤더 X-Device-Id · X-Mode · X-Frame
///   GET  /latest/<장치>       최신 한 장
///   GET  /status              장치별 상태
class DoorCamServer {
  static const _maxBody = 300 * 1024;

  // 장치 이름이 마구 쌓이지 않게 제한한다
  static const _maxDevices = 8;

  HttpServer? _server;
  Timer? _retry;
  bool _stopped = false;
  final _frames = StreamController<DoorFrame>.broadcast();

  final latest = <String, DoorFrame>{};

  Stream<DoorFrame> get frames => _frames.stream;

  Future<void> start() async {
    if (_server != null) return;
    _stopped = false;
    try {
      final server = _server = await HttpServer.bind(InternetAddress.anyIPv4, doorCamPort);
      server.idleTimeout = const Duration(seconds: 60); // 카메라가 keep-alive 로 연결을 계속 쓴다
      server.listen(_handle, onError: (_) {}, onDone: () {
        _server = null;
        if (!_stopped) _retry = Timer(const Duration(seconds: 10), start);
      });
    } catch (e) {
      stderr.writeln('[doorcam] :$doorCamPort 를 열지 못함 ($e)');
      _server = null;
      _retry = Timer(const Duration(seconds: 10), start);
    }
  }

  Future<void> _handle(HttpRequest r) async {
    try {
      if (!_fromLan(r.connectionInfo?.remoteAddress)) return _reply(r, HttpStatus.forbidden, 'LAN only');
      if (r.method == 'POST' && r.uri.path == '/api/camera/frames') return _frame(r);
      final seg = r.uri.pathSegments;
      if (r.method == 'GET' && seg.length == 2 && seg[0] == 'latest') {
        final f = latest[seg[1]];
        if (f == null) return _reply(r, HttpStatus.notFound, 'no frame yet');
        r.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('image', 'jpeg')
          ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
          ..add(f.jpeg);
        return r.response.close();
      }
      if (r.method == 'GET' && r.uri.path == '/status') {
        final now = DateTime.now();
        final j = {
          for (final f in latest.values) f.device: {'seq': f.seq, 'mode': f.mode, 'bytes': f.jpeg.length, 'age_s': now.difference(f.at).inMilliseconds / 1000},
        };
        return _reply(r, HttpStatus.ok, jsonEncode(j), json: true);
      }
      return _reply(r, HttpStatus.notFound, 'not found');
    } catch (_) {
      try {
        await r.response.close();
      } catch (_) {}
    }
  }

  Future<void> _frame(HttpRequest r) async {
    if (r.contentLength > _maxBody) return _reply(r, HttpStatus.requestEntityTooLarge, 'too large');
    final body = await r.fold<BytesBuilder>(BytesBuilder(copy: false), (b, c) => b..add(c));
    final jpeg = body.takeBytes();
    if (jpeg.length > _maxBody || jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
      return _reply(r, HttpStatus.badRequest, 'not a jpeg', drained: true);
    }
    final device = r.headers.value('x-device-id') ?? 'cam1';
    if (!latest.containsKey(device) && latest.length >= _maxDevices) return _reply(r, HttpStatus.tooManyRequests, 'too many devices', drained: true);
    final f = DoorFrame(device, r.headers.value('x-mode') ?? 'idle', int.tryParse(r.headers.value('x-frame') ?? '') ?? 0, jpeg, DateTime.now());
    latest[f.device] = f;
    await _reply(r, HttpStatus.ok, '{"ok":true}', json: true, drained: true);
    _frames.add(f); // 12fps 가 밀리지 않게 응답부터 보낸다
  }

  Future<void> _reply(HttpRequest r, int status, String text, {bool json = false, bool drained = false}) async {
    if (!drained) await r.drain<void>();
    r.response
      ..statusCode = status
      ..headers.contentType = json ? ContentType.json : ContentType.text
      ..write(text);
    await r.response.close();
  }

  // 공유기가 이 포트를 밖으로 열어 둬서 사설망 주소만 받는다
  static bool _fromLan(InternetAddress? a) {
    if (a == null) return false;
    if (a.isLoopback) return true;
    final b = a.rawAddress;
    if (b.length != 4) return false;
    return b[0] == 10 || (b[0] == 192 && b[1] == 168) || (b[0] == 172 && b[1] >= 16 && b[1] <= 31);
  }

  void stop() {
    _stopped = true;
    _retry?.cancel();
    _server?.close(force: true);
    _server = null;
  }
}
