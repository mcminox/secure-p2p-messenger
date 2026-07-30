import 'dart:convert';

abstract final class InviteCodec {
  static const wireVersion = 1;
  static const quickPrefix = 'dartaut-invite:';

  static String buildJson({
    required String displayName,
    required String ed25519Hex,
    String? x25519Hex,
  }) {
    final m = <String, dynamic>{
      'dart_aut': wireVersion,
      'n': displayName,
      'ed': ed25519Hex,
    };
    if (x25519Hex != null && x25519Hex.isNotEmpty) {
      m['x'] = x25519Hex;
    }
    return const JsonEncoder.withIndent('  ').convert(m);
  }

  static String buildCompactJson({
    required String displayName,
    required String ed25519Hex,
    String? x25519Hex,
  }) {
    final m = <String, dynamic>{
      'dart_aut': wireVersion,
      'n': displayName,
      'ed': ed25519Hex,
    };
    if (x25519Hex != null && x25519Hex.isNotEmpty) {
      m['x'] = x25519Hex;
    }
    return jsonEncode(m);
  }

  static String buildQuickToken({
    required String displayName,
    required String ed25519Hex,
    String? x25519Hex,
  }) {
    final compact = buildCompactJson(
      displayName: displayName,
      ed25519Hex: ed25519Hex,
      x25519Hex: x25519Hex,
    );
    final b64 = base64UrlEncode(utf8.encode(compact));
    return '$quickPrefix$b64';
  }

  static Map<String, dynamic>? tryParse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final quick = _tryParseQuickToken(s);
    if (quick != null) return quick;
    try {
      final j = jsonDecode(s);
      if (j is Map<String, dynamic>) return _normalize(j);
      if (j is Map) return _normalize(Map<String, dynamic>.from(j));
    } catch (_) {}
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final j = jsonDecode(s.substring(start, end + 1));
        if (j is Map<String, dynamic>) return _normalize(j);
        if (j is Map) return _normalize(Map<String, dynamic>.from(j));
      } catch (_) {}
    }
    final tokenMatch = RegExp(r'dartaut-invite:[A-Za-z0-9\-_+=/]+').firstMatch(s);
    if (tokenMatch != null) {
      return _tryParseQuickToken(tokenMatch.group(0)!);
    }
    return null;
  }

  static Map<String, dynamic>? _tryParseQuickToken(String raw) {
    final i = raw.indexOf(quickPrefix);
    if (i < 0) return null;
    final token = raw.substring(i).trim();
    if (!token.startsWith(quickPrefix)) return null;
    final payload = token.substring(quickPrefix.length).trim();
    if (payload.isEmpty) return null;
    try {
      final json = utf8.decode(base64Url.decode(base64Url.normalize(payload)));
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return _normalize(decoded);
      if (decoded is Map) return _normalize(Map<String, dynamic>.from(decoded));
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic>? _normalize(Map<String, dynamic> j) {
    final v = j['dart_aut'];
    if (v is! num || v.toInt() != wireVersion) return null;
    final n = j['n'] as String?;
    final ed = j['ed'] as String?;
    if (n == null || ed == null) return null;
    return {
      'n': n.trim(),
      'ed': ed.trim().replaceAll(RegExp(r'\s'), '').toLowerCase(),
      if (j['x'] != null) 'x': (j['x'] as String).trim().replaceAll(RegExp(r'\s'), '').toLowerCase(),
    };
  }
}
