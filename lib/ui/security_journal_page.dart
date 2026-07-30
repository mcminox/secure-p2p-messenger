import 'package:flutter/material.dart';

import '../security/security_audit_log.dart';
import 'widgets/app_snack.dart';
import 'widgets/messenger_backdrop.dart';
import 'widgets/secure_ui.dart';

class SecurityJournalPage extends StatefulWidget {
  const SecurityJournalPage({super.key});

  @override
  State<SecurityJournalPage> createState() => _SecurityJournalPageState();
}

class _SecurityJournalPageState extends State<SecurityJournalPage> {
  List<String> _lines = const [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final lines = await SecurityAuditLog.instance.readRecent();
    if (!mounted) return;
    setState(() {
      _lines = lines.reversed.toList();
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MessengerBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Security Journal'),
          actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Поделиться',
            onPressed: _busy
                ? null
                : () async {
                    await SecurityAuditLog.instance.shareAll();
                  },
            icon: const Icon(Icons.share_rounded),
          ),
          IconButton(
            tooltip: 'Очистить',
            onPressed: _busy
                ? null
                : () async {
                    await SecurityAuditLog.instance.clear();
                    await _load();
                    if (context.mounted) AppSnack.show(context, 'Журнал очищен');
                  },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          ],
        ),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : _lines.isEmpty
                ? const Center(child: Text('Журнал пуст'))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => SecureCard(
                      padding: const EdgeInsets.all(10),
                      child: SelectableText(
                        _lines[i],
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ),
      ),
    );
  }
}
