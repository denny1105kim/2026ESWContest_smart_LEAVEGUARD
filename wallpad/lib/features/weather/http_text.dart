import 'dart:convert';
import 'dart:io';

/// 단계마다 [timeout] 을 거는 GET.
Future<String> getText(Uri uri, Duration timeout) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(uri).timeout(timeout);
    final res = await req.close().timeout(timeout);
    return await res.transform(utf8.decoder).join().timeout(timeout);
  } finally {
    client.close(force: true);
  }
}
