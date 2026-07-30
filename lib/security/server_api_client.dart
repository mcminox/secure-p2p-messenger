import 'dart:convert';
import 'dart:io';

import '../prefs/app_preferences.dart';

class ServerApiClient {
  ServerApiClient({AppPreferences? prefs}) : _prefs = prefs ?? AppPreferences();

  final AppPreferences _prefs;

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    final baseUrl = await _prefs.serverBaseUrl();
    final pin = await _prefs.serverPin();
    if (baseUrl.isEmpty) {
      throw StateError('Сервер не настроен.');
    }

    final url = Uri.parse(baseUrl + path);
    final client = HttpClient();
    final req = await client.postUrl(url);
    req.headers.contentType = ContentType.json;
    req.headers.set('x-request-id', _reqId());
    req.headers.set('x-timestamp', DateTime.now().toUtc().toIso8601String());
    if (accessToken != null && accessToken.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    }
    req.write(jsonEncode(body));
    final resp = await req.close();
    final raw = await utf8.decodeStream(resp);
    final parsed = raw.isEmpty ? <String, dynamic>{} : (jsonDecode(raw) as Map<String, dynamic>);
    if (pin.isNotEmpty) {
      final got = resp.headers.value('x-cert-pin') ?? '';
      if (got != pin) {
        throw StateError('TLS pin mismatch.');
      }
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError(parsed['error']?.toString() ?? 'Server error ${resp.statusCode}');
    }
    return parsed;
  }

  String _reqId() {
    final ms = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final rnd = (DateTime.now().millisecondsSinceEpoch ^ 0x5A17).toRadixString(16);
    return '$ms-$rnd';
  }
}
