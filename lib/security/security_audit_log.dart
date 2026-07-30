import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SecurityAuditLog {
  SecurityAuditLog._();
  static final SecurityAuditLog instance = SecurityAuditLog._();

  Future<File> _file() async {
    final root = await getApplicationSupportDirectory();
    final f = File('${root.path}/security_audit.jsonl');
    if (!await f.exists()) {
      await f.create(recursive: true);
    }
    return f;
  }

  Future<void> append(
    String event, {
    Map<String, dynamic>? details,
  }) async {
    try {
      final f = await _file();
      final row = <String, dynamic>{
        'ts': DateTime.now().toUtc().toIso8601String(),
        'event': event,
        if (details != null && details.isNotEmpty) 'details': details,
      };
      await f.writeAsString('${jsonEncode(row)}\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  Future<List<String>> readRecent({int maxLines = 300}) async {
    try {
      final f = await _file();
      final lines = await f.readAsLines();
      if (lines.length <= maxLines) return lines;
      return lines.sublist(lines.length - maxLines);
    } catch (_) {
      return [];
    }
  }

  Future<void> clear() async {
    try {
      final f = await _file();
      await f.writeAsString('', flush: true);
    } catch (_) {}
  }

  Future<void> shareAll() async {
    final lines = await readRecent(maxLines: 2000);
    final body = lines.join('\n');
    if (body.trim().isEmpty) return;
    await Share.share(body, subject: 'Dart AUT security audit');
  }
}
