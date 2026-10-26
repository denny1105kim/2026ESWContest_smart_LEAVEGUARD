import 'dart:convert';
import 'dart:io';

import '../../core/config/device_config.dart';
import '../../shared/time_text.dart';

class DayEvent {
  final String time; // '10:00' 또는 '종일'
  final String title;

  const DayEvent(this.time, this.title);
}

/// 캘린더 서버 접속 정보. 구글 토큰은 서버가 갖고 월패드는 일정만 받는다.
class CalendarServerConfig {
  final String url;
  final String key;

  const CalendarServerConfig({required this.url, required this.key});

  /// device.json 의 {"url", "key"}. 값이 모자라면 null.
  static CalendarServerConfig? fromJson(Map<String, dynamic> j) {
    final url = j['url'], key = j['key'];
    if (url is! String || key is! String || url.trim().isEmpty || key.trim().isEmpty) return null;
    return CalendarServerConfig(url: url.trim().replaceAll(RegExp(r'/+$'), ''), key: key.trim());
  }
}

class LinkSession {
  final String id;
  final String url;
  final DateTime expiresAt;
  final Duration pollInterval;

  const LinkSession({required this.id, required this.url, required this.expiresAt, required this.pollInterval});
}

enum LinkStatus { pending, linked, denied, expired, failed }

enum CalendarLink { linked, notLinked, needsReauth }

class TodayResult {
  final CalendarLink link;
  final List<DayEvent> events;

  const TodayResult(this.link, [this.events = const []]);
}

class FamilyEvent {
  final String id; // 완료 체크 저장 키
  final String title;
  final String timeLabel; // '08:00–09:00', '08:00' 또는 '종일'

  const FamilyEvent(this.id, this.title, this.timeLabel);
}

enum FamilyCalendar { ok, none, needsReauth }

class FamilyDay {
  final FamilyCalendar state;
  final List<FamilyEvent> today;
  final List<FamilyEvent> tomorrow;

  const FamilyDay(this.state, {this.today = const [], this.tomorrow = const []});

  /// {"today": [일정…], "tomorrow": [일정…]}, 일정 = {"id", "title", "start", "end", "all_day"}
  factory FamilyDay.fromJson(Map<String, dynamic> j) {
    List<FamilyEvent> list(Object? xs) => [
          if (xs is List)
            for (final e in xs)
              if (e is Map<String, dynamic>) _familyEvent(e),
        ];
    return FamilyDay(FamilyCalendar.ok, today: list(j['today']), tomorrow: list(j['tomorrow']));
  }

  static FamilyEvent _familyEvent(Map<String, dynamic> e) {
    final title = (e['title'] as String?)?.trim();
    final startText = e['start'] as String? ?? '', endText = e['end'] as String? ?? '';
    final start = DateTime.tryParse(startText), end = DateTime.tryParse(endText);
    // 서버가 tz 에 맞춰 준 시각을 그대로 쓴다 (보드 시간대 무관)
    String? hm(String s) {
      final m = RegExp(r'T(\d\d):(\d\d)').firstMatch(s);
      return m == null ? null : '${m[1]}:${m[2]}';
    }

    final from = hm(startText), to = hm(endText);
    final time = e['all_day'] == true || start == null || from == null
        ? '종일'
        : end == null || to == null || !end.isAfter(start)
            ? from
            : '$from–$to';
    // id 가 없으면 같은 일정이 같은 키가 되게 만든다
    final id = e['id'] as String? ?? '${title ?? ''}@${e['start'] ?? ''}';
    return FamilyEvent(id, title == null || title.isEmpty ? '(제목 없음)' : title, time);
  }
}

class CalendarServer {
  final CalendarServerConfig config;
  final Duration timeout;

  CalendarServer(this.config, {this.timeout = const Duration(seconds: 15)});

  static Future<CalendarServer?> load() async {
    final j = await DeviceConfig.load();
    final c = j == null ? null : CalendarServerConfig.fromJson(j);
    return c == null ? null : CalendarServer(c);
  }

  // 같은 사용자의 이전 QR 은 서버에서 무효가 된다
  Future<LinkSession> createSession(String user) async {
    final (code, j) = await _send('POST', '/api/v1/link-sessions', body: {'user': user});
    if (code != 201 && code != 200) throw _error(code, j);
    return LinkSession(
      id: j['session_id'] as String,
      url: j['link_url'] as String,
      expiresAt: DateTime.parse(j['expires_at'] as String),
      pollInterval: Duration(seconds: (j['poll_interval'] as num?)?.toInt() ?? 3),
    );
  }

  Future<LinkStatus> pollSession(String sessionId) async {
    final (code, j) = await _send('GET', '/api/v1/link-sessions/${Uri.encodeComponent(sessionId)}');
    if (code == 404) return LinkStatus.expired;
    if (code != 200) throw _error(code, j);
    return LinkStatus.values.asNameMap()[j['status']] ?? LinkStatus.failed;
  }

  Future<CalendarLink> status(String user) async {
    final (code, j) = await _send('GET', _userPath(user));
    if (code != 200) throw _error(code, j);
    if (j['linked'] != true) return CalendarLink.notLinked;
    return j['needs_reauth'] == true ? CalendarLink.needsReauth : CalendarLink.linked;
  }

  Future<TodayResult> fetchToday(String user, {String tz = 'Asia/Seoul'}) async {
    final (code, j) = await _send('GET', '${_userPath(user)}/today', query: {'tz': tz});
    if (code == 404) return const TodayResult(CalendarLink.notLinked);
    if (code == 409) return const TodayResult(CalendarLink.needsReauth);
    if (code != 200) throw _error(code, j);
    final items = (j['events'] as List?) ?? const [];
    return TodayResult(CalendarLink.linked, [for (final e in items) _toEvent(e as Map<String, dynamic>)]);
  }

  Future<FamilyDay> fetchFamilyToday({String tz = 'Asia/Seoul'}) async {
    final (code, j) = await _send('GET', '/api/v1/family/calendar/today', query: {'tz': tz});
    if (code == 404) return const FamilyDay(FamilyCalendar.none);
    if (code == 409) return const FamilyDay(FamilyCalendar.needsReauth);
    if (code != 200) throw _error(code, j);
    return FamilyDay.fromJson(j);
  }

  Future<void> unlink(String user) async {
    final (code, j) = await _send('DELETE', _userPath(user));
    if (code != 204 && code != 200) throw _error(code, j);
  }

  String _userPath(String user) => '/api/v1/users/${Uri.encodeComponent(user)}/calendar';

  Future<(int, Map<String, dynamic>)> _send(String method, String path, {Map<String, String>? query, Map<String, dynamic>? body}) async {
    final uri = Uri.parse('${config.url}$path').replace(queryParameters: query);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.openUrl(method, uri).timeout(timeout);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config.key}');
      if (body != null) {
        // chunked 를 못 읽는 서버가 있어 길이를 정한다
        final bytes = utf8.encode(jsonEncode(body));
        req.headers.contentType = ContentType.json;
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      final j = text.isEmpty ? null : jsonDecode(text);
      return (res.statusCode, j is Map<String, dynamic> ? j : <String, dynamic>{});
    } finally {
      client.close(force: true);
    }
  }

  static HttpException _error(int code, Map<String, dynamic> j) => HttpException('HTTP $code ${j['error'] ?? ''}'.trim());

  static DayEvent _toEvent(Map<String, dynamic> e) {
    final title = (e['title'] as String?)?.trim();
    final start = e['start'] as String?;
    if (e['all_day'] == true || start == null) return DayEvent('종일', title ?? '(제목 없음)');
    final t = DateTime.tryParse(start)?.toLocal();
    return DayEvent(t == null ? '종일' : hhmm(t), title ?? '(제목 없음)');
  }
}
