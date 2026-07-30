import 'dart:convert';

abstract final class RtcSignalingCodec {
  static const wireVersion = 1;

  static String buildJson({
    required String role,
    required String conversationId,
    required String sdp,
  }) {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'dart_aut_rtc': wireVersion,
      'role': role,
      'cid': conversationId,
      'sdp': sdp,
    });
  }

  static ({String role, String cid, String sdp})? tryParse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    Map<String, dynamic>? m;
    try {
      final j = jsonDecode(s);
      if (j is Map<String, dynamic>) m = j;
      if (j is Map) m = Map<String, dynamic>.from(j);
    } catch (_) {}
    if (m == null) {
      final start = s.indexOf('{');
      final end = s.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          final j = jsonDecode(s.substring(start, end + 1));
          if (j is Map<String, dynamic>) m = j;
          if (j is Map) m = Map<String, dynamic>.from(j);
        } catch (_) {}
      }
    }
    if (m == null) return null;
    final v = m['dart_aut_rtc'];
    if (v is! num || v.toInt() != wireVersion) return null;
    final role = m['role'] as String?;
    final cid = m['cid'] as String?;
    final sdp = m['sdp'] as String?;
    if (role == null || cid == null || sdp == null) return null;
    if (role != 'offer' && role != 'answer') return null;
    return (role: role, cid: cid, sdp: sdp.trim());
  }
}
