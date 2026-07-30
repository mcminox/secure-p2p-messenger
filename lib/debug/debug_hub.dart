import 'package:flutter/foundation.dart';

class ConnectionEvent {
  ConnectionEvent({
    required this.id,
    required this.label,
    required this.openedAt,
    this.closedAt,
    this.ok = true,
    this.suspicious = false,
    this.detail,
  });

  final String id;
  final String label;
  final DateTime openedAt;
  DateTime? closedAt;
  bool ok;
  bool suspicious;
  String? detail;

  bool get isOpen => closedAt == null;
}

class DebugHub extends ChangeNotifier {
  DebugHub._();
  static final DebugHub instance = DebugHub._();

  final List<String> logLines = [];
  final List<ConnectionEvent> connections = [];
  static const maxLog = 400;

  void log(String line) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    logLines.add('[$ts] $line');
    while (logLines.length > maxLog) {
      logLines.removeAt(0);
    }
    notifyListeners();
  }

  String openConnection(String label, {String? id}) {
    final cid = id ?? '${DateTime.now().microsecondsSinceEpoch}';
    connections.insert(
      0,
      ConnectionEvent(id: cid, label: label, openedAt: DateTime.now()),
    );
    while (connections.length > 120) {
      connections.removeLast();
    }
    notifyListeners();
    return cid;
  }

  void closeConnection(String id, {required bool ok, bool suspicious = false, String? detail}) {
    for (final c in connections) {
      if (c.id == id) {
        c.closedAt = DateTime.now();
        c.ok = ok;
        c.suspicious = suspicious || !ok;
        c.detail = detail;
        break;
      }
    }
    notifyListeners();
  }

  void flagSuspicious(String id, String reason) {
    for (final c in connections) {
      if (c.id == id) {
        c.suspicious = true;
        c.detail = reason;
        break;
      }
    }
    notifyListeners();
  }

  void clearLogs() {
    logLines.clear();
    notifyListeners();
  }
}
