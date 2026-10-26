import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// 음성 메모: 녹음 → whisper 받아쓰기 → EXAONE 으로 1~3줄 다듬기.
class VoiceMemo {
  VoiceMemo({this.models = '/data/leaveguard-models'});

  final String models;

  static const maxRecord = Duration(seconds: 10);
  static const silenceToStop = Duration(milliseconds: 1500);
  static const noSpeechGiveUp = Duration(seconds: 6);
  static const _rate = 16000;
  static const _port = 8099;
  static const _sttPort = 8098;
  static const _llmModel = 'exaone-4.0-1.2b-Q4_K_M.gguf';
  static const _sttModel = 'ggml-small-q8_0.bin';

  static const _slots = 3;

  Process? _rec;
  Process? _llm;
  Process? _stt;
  var _stopRequested = false;

  Future<String?>? _early;
  var _earlyBusy = false;
  Uint8List? _queued;
  var _spokeAfterEarly = false;
  final _refined = <String, Future<String?>>{};

  String get _cache => Platform.environment['XDG_CACHE_HOME'] ?? '/tmp';

  // 앱 사용자는 /dev/snd 를 못 열어 시스템 모드 PulseAudio 에 붙는다
  Map<String, String> get _pulseEnv => {'PULSE_SERVER': 'unix:/run/pulse/native', 'HOME': _cache};

  static const micVolume = 60;

  // 앱 시작 때 띄우면 얼굴 모델과 겹쳐 Pi5 가 저전압으로 꺼져서, 메모 창을 열 때 띄운다
  Future<void> warmUp() async {
    if (_llm != null || await _llmReady()) return _startStt();
    try {
      final log = File('$_cache/leaveguard_llm.log').openWrite(mode: FileMode.append);
      final p = _llm = await Process.start('$models/llama-server',
          ['-m', '$models/$_llmModel', '-t', '3', '-tb', '4', '-c', '${512 * _slots}', '-np', '$_slots', '--host', '127.0.0.1', '--port', '$_port'],
          workingDirectory: models);
      p.stdin.close().ignore();
      p.stdout.listen(log.add);
      p.stderr.listen(log.add);
      p.exitCode.then((_) {
        log.close().ignore();
        _llm = null;
      });
      _primeWhenReady().then((_) => _startStt()).ignore();
    } catch (_) {
      _llm = null;
    }
  }

  Future<void> _startStt() async {
    if (_stt != null || await _ready(_sttPort)) return;
    final stt = '$models/stt';
    try {
      final p = _stt = await Process.start('$stt/whisper-server',
          ['-m', '$stt/$_sttModel', '-l', 'ko', '-t', '4', '-bs', '1', '-bo', '1', '-nf', '-nt', '--host', '127.0.0.1', '--port', '$_sttPort'],
          workingDirectory: stt);
      p.stdin.close().ignore();
      p.stdout.drain<void>().ignore();
      p.stderr.drain<void>().ignore();
      p.exitCode.then((_) => _stt = null);
    } catch (_) {
      _stt = null;
    }
  }

  Future<void> _primeWhenReady() async {
    for (var i = 0; i < 60 && _llm != null; i++) {
      if (await _ready(_port)) {
        await Future.wait([for (var k = 0; k < _slots; k++) _complete(_prompt(''), nPredict: 1)]);
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<bool> _llmReady() => _ready(_port);

  Future<bool> _ready(int port) async {
    try {
      final c = HttpClient()..connectionTimeout = const Duration(milliseconds: 500);
      final res = await (await c.getUrl(Uri.parse('http://127.0.0.1:$port/health'))).close().timeout(const Duration(seconds: 1));
      c.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 말이 없었으면 null. [onLevel] 은 0~1.
  Future<String?> record({void Function(double level)? onLevel, void Function(Duration elapsed)? onTick}) async {
    _stopRequested = false;
    _early = null;
    _queued = null;
    _spokeAfterEarly = false;
    _refined.clear();
    final early = await _ready(_sttPort);
    final pcm = BytesBuilder(copy: false);
    // 카메라 마이크 기본값이 최대라 방 소음이 너무 크다
    try {
      await Process.run('pactl', ['set-source-volume', '@DEFAULT_SOURCE@', '$micVolume%'], environment: _pulseEnv);
    } catch (_) {}
    final Process p;
    try {
      p = _rec = await Process.start(
        'gst-launch-1.0',
        ['-q', 'pulsesrc', '!', 'audioconvert', '!', 'audioresample', '!', 'audio/x-raw,format=S16LE,rate=$_rate,channels=1', '!', 'fdsink', 'fd=1'],
        environment: _pulseEnv,
      );
    } catch (_) {
      return null;
    }
    p.stdin.close().ignore();
    p.stderr.drain<void>().ignore();
    final done = Completer<void>();
    // 0.2~0.8초 중앙값을 소음 기준으로, 0.3초 넘게 크면 말 시작
    final noise = <double>[];
    double? floor;
    var spoke = false;
    var loudRun = 0, quietMs = 0, totalMs = 0;
    final frame = <int>[];
    void stop() {
      if (!done.isCompleted) done.complete();
    }

    final sub = p.stdout.listen((chunk) {
      pcm.add(chunk);
      frame.addAll(chunk);
      while (frame.length >= _rate ~/ 10 * 2) {
        final bytes = Uint8List.fromList(frame.sublist(0, _rate ~/ 10 * 2));
        frame.removeRange(0, bytes.length);
        final s = bytes.buffer.asInt16List();
        var sum = 0.0;
        for (final v in s) {
          sum += v * v;
        }
        final rms = sqrt(sum / s.length);
        totalMs += 100;
        onTick?.call(Duration(milliseconds: totalMs));
        if (totalMs <= 800) {
          if (totalMs > 200) noise.add(rms);
          continue;
        }
        floor ??= (noise..sort())[noise.length ~/ 2];
        final base = max(floor!, 200.0);
        final loud = rms > max(base * 2.2, base + 800);
        onLevel?.call(((rms - base) / (base * 6)).clamp(0.0, 1.0));
        loudRun = loud ? loudRun + 1 : 0;
        if (loudRun >= 3) spoke = true;
        if (_early != null && rms > max(base * 1.6, base + 400)) _spokeAfterEarly = true;
        if (loud) {
          quietMs = 0;
        } else if (spoke) {
          quietMs += 100;
        }
        if (early && spoke && quietMs == 500 && (_early == null || _spokeAfterEarly)) {
          _spokeAfterEarly = false;
          _sendEarly(pcm.toBytes());
        }
        if ((spoke && quietMs >= silenceToStop.inMilliseconds) ||
            totalMs >= maxRecord.inMilliseconds ||
            (!spoke && totalMs >= noSpeechGiveUp.inMilliseconds) ||
            _stopRequested) {
          stop();
        }
      }
    }, onDone: stop);
    await done.future.timeout(maxRecord + const Duration(seconds: 2), onTimeout: () {});
    p.kill();
    await sub.cancel();
    _rec = null;
    if (!spoke && !_stopRequested) return null;
    final path = '$_cache/leaveguard_memo.wav';
    await File(path).writeAsBytes(_wav(pcm.takeBytes()));
    return path;
  }

  void stopRecording() => _stopRequested = true;

  void cancel() {
    _stopRequested = true;
    _rec?.kill();
  }

  static Uint8List _wav(Uint8List pcm) {
    final h = ByteData(44);
    void str(int o, String s) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    h.setUint32(4, 36 + pcm.length, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    h
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, _rate, Endian.little)
      ..setUint32(28, _rate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    str(36, 'data');
    h.setUint32(40, pcm.length, Endian.little);
    return (BytesBuilder()
          ..add(h.buffer.asUint8List())
          ..add(pcm))
        .takeBytes();
  }

  void _sendEarly(Uint8List pcm) {
    if (_earlyBusy) {
      _queued = pcm;
      return;
    }
    _earlyBusy = true;
    _early = _transcribeServer(pcm).then((text) {
      if (text != null && !_spokeAfterEarly && _queued == null) {
        for (final c in clauses(text)) {
          _refined.putIfAbsent(c, () => _complete(_prompt(c)));
        }
      }
      return text;
    }).whenComplete(() {
      _earlyBusy = false;
      final next = _queued;
      _queued = null;
      if (next != null) _sendEarly(next);
    });
  }

  Future<String?> transcribe(String wav) async {
    for (Future<String?>? early = _early; early != null; early = _early) {
      final text = await early;
      if (!identical(early, _early)) continue;
      if (!_spokeAfterEarly && text != null) return text.isEmpty ? null : text;
      break;
    }
    if (await _ready(_sttPort)) {
      final pcm = await File(wav).readAsBytes();
      final text = await _transcribeServer(pcm.sublist(44));
      if (text != null) return text.isEmpty ? null : text;
    }
    final stt = '$models/stt';
    try {
      final r = await Process.run('$stt/whisper-cli',
              ['-m', '$stt/$_sttModel', '-l', 'ko', '-t', '4', '-bs', '1', '-bo', '1', '-nf', '-ac', '${_audioCtx(await File(wav).length() - 44)}', '-nt', '-np', '-f', wav])
          .timeout(const Duration(seconds: 20));
      return _clean(r.stdout as String);
    } catch (_) {
      return null;
    }
  }

  static int _audioCtx(int pcmBytes) => min(1500, max(500, pcmBytes * 60 ~/ (_rate * 2) + 100));

  // 소음에서 지어낸 대사와 [음악] 같은 표시를 걷는다
  static String? _clean(String raw) {
    final text = raw
        .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), '')
        .replaceAll(RegExp(r'(^|\s)-\s'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.isEmpty ? null : text;
  }

  Future<String?> _transcribeServer(Uint8List pcm) async {
    const boundary = 'leaveguardmemo';
    try {
      final c = HttpClient();
      final req = await c.postUrl(Uri.parse('http://127.0.0.1:$_sttPort/inference'));
      req.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': boundary});
      void field(String name, String value) =>
          req.write('--$boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n$value\r\n');
      field('audio_ctx', '${_audioCtx(pcm.length)}');
      field('response_format', 'text');
      req.write('--$boundary\r\nContent-Disposition: form-data; name="file"; filename="memo.wav"\r\nContent-Type: audio/wav\r\n\r\n');
      req.add(_wav(pcm));
      req.write('\r\n--$boundary--\r\n');
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res.transform(const Utf8Decoder(allowMalformed: true)).join();
      c.close();
      if (res.statusCode != 200) return null;
      return _clean(body.replaceAll('\uFFFD', '')) ?? '';
    } catch (_) {
      return null;
    }
  }

  static const _system = '너는 음성 메모 한 토막을 내일 아침 메모 한 줄로 다듬는다. 말한 낱말만 쓰고 새 사실을 지어내지 마. '
      "군말과 끝말은 버리고 18자 안으로: 물건은 '~ 챙기기', 일정은 '세 시 치과'처럼 시간과 장소, 할 일은 '~하기'. 답은 그 한 줄만.";
  static const _shots = [
    ('어 내일 아침에 그 노트북 충전기 꼭 챙겨야 돼', '노트북 충전기 챙기기'),
    ('사원증이랑 지갑 챙기고', '사원증 · 지갑 챙기기'),
    ('음 아홉 시에 팀 회의 있어', '아홉 시 팀 회의'),
    ('우체국 가서 택배 보내야 돼', '우체국에서 택배 보내기'),
    ('세탁소에서 바지 찾아와야 돼', '세탁소에서 바지 찾아오기'),
  ];

  // 1.2B 는 한 번에 여러 개를 시키면 빠뜨려서 토막마다 따로 다듬는다
  Future<List<String>> refine(String said) async {
    final parts = clauses(said);
    if (parts.isEmpty) return [roughly(said)];
    // 모델이 아직 올라오는 중이면 조금 기다린다
    var ready = await _llmReady();
    for (var i = 0; !ready && _llm != null && i < 10; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      ready = await _llmReady();
    }
    Future<String?> line(String c) async => await _refined[c] ?? await _complete(_prompt(c));
    final lines = await Future.wait([for (final c in parts) ready ? line(c) : Future.value(null)]);
    return [
      for (var i = 0; i < parts.length; i++) lines[i] != null && grounded(parts[i], lines[i]!) ? lines[i]! : roughly(parts[i]),
    ].where((l) => l.isNotEmpty).toList();
  }

  static String _prompt(String clause) {
    final b = StringBuffer('[|system|]\n$_system[|endofturn|]\n');
    for (final (a, r) in _shots) {
      b.write('[|user|]\n$a[|endofturn|]\n[|assistant|]\n<think>\n\n</think>\n\n$r[|endofturn|]\n');
    }
    if (clause.isNotEmpty) b.write('[|user|]\n$clause[|endofturn|]\n[|assistant|]\n<think>\n\n</think>\n\n');
    return b.toString();
  }

  Future<String?> _complete(String prompt, {int nPredict = 24}) async {
    try {
      final c = HttpClient();
      final req = await c.postUrl(Uri.parse('http://127.0.0.1:$_port/completion'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'prompt': prompt, 'n_predict': nPredict, 'temperature': 0, 'cache_prompt': true, 'stop': ['[|endofturn|]', '\n']}));
      final res = await req.close().timeout(const Duration(seconds: 6));
      final body = await res.transform(utf8.decoder).join();
      c.close();
      return ((jsonDecode(body) as Map)['content'] as String? ?? '').replaceFirst(RegExp(r'^\s*[-•·*]\s*'), '').trim();
    } catch (_) {
      return null;
    }
  }

  static const _fillers = {'어', '음', '아', '그', '저', '막', '내일', '꼭', '좀'};

  /// "그리고" 같은 접속어와 '-고' 어미에서 최대 3토막으로 나눈다.
  static List<String> clauses(String said) {
    final t = said.replaceAll(RegExp(r'\s+'), ' ').trim();
    final out = <String>[];
    for (final p in t.split(RegExp(r'\s*(?:아\s*맞다|그리고\s*나서|그리고|그\s?다음에)\s*'))) {
      final words = p.split(' ').where((w) => w.isNotEmpty).toList();
      var cur = <String>[];
      for (var i = 0; i < words.length; i++) {
        final w = words[i];
        cur.add(w);
        final next = i + 1 < words.length ? words[i + 1] : '';
        if (next.isNotEmpty && w.length >= 2 && w.endsWith('고') && !w.endsWith('라고') && !RegExp(r'^(가|와|오|있|해)').hasMatch(next)) {
          out.add(cur.join(' '));
          cur = [];
        }
      }
      if (cur.isNotEmpty) out.add(cur.join(' '));
    }
    final res = <String>[];
    for (final c in out) {
      final core = c.split(' ').where((w) => !_fillers.contains(w)).join();
      if (core.length < 3 && res.isNotEmpty) {
        res[res.length - 1] = '${res.last} $c';
      } else if (core.length >= 2) {
        res.add(c);
      }
    }
    return res.take(3).toList();
  }

  /// 다듬은 낱말이 모두 들은 말에 있나 (말꼬리 제외).
  static bool grounded(String said, String out) {
    if (out.isEmpty || out.length > 26) return false;
    final s = said.replaceAll(' ', '');
    for (final w in out.split(RegExp(r'\s+'))) {
      final stem = w.replaceAll(RegExp(r'(에서|한테|에게|으로|로|을|를|이|가|은|는|에)?(챙기기|하기|가기|보내기|사기|찾기|버리기|들고|가져가기|기)$'), '');
      if (stem.length >= 2 && !s.contains(stem.substring(0, 2))) return false;
    }
    return true;
  }

  /// LLM 없이 군말·끝말만 걷는다.
  static String roughly(String said) {
    var t = ' $said ';
    for (final f in ['어', '음', '아', '그', '저', '내일', '아침에', '꼭', '좀', '아 맞다', '맞다', '잊지 말자', '잊지 마']) {
      t = t.replaceAll(' $f ', ' ');
    }
    t = t
        .replaceAll(RegExp(r'\s*(해야\s?(돼|해|된다|되는데)|하기로\s?했어|하자|할 것|해야지)\s*$'), '하기')
        .replaceAll(RegExp(r'와야\s?(돼|해|된다)\s*$'), '오기')
        .replaceAll(RegExp(r'가야\s?(돼|해|된다)\s*$'), '가기')
        .replaceAllMapped(RegExp(r'(\S)고\s*$'), (m) => '${m[1]}기')
        .replaceAll(RegExp(r'\s+(있어|있음|했어)\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.length > 26 ? t.substring(0, 26) : t;
  }
}
