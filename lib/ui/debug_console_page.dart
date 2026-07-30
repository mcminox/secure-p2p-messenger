import 'package:flutter/material.dart';

import '../debug/debug_hub.dart';

class DebugConsolePage extends StatefulWidget {
  const DebugConsolePage({super.key});

  @override
  State<DebugConsolePage> createState() => _DebugConsolePageState();
}

class _DebugConsolePageState extends State<DebugConsolePage> {
  final _scrollLog = ScrollController();
  final _scrollConn = ScrollController();

  @override
  void initState() {
    super.initState();
    DebugHub.instance.addListener(_onHub);
  }

  void _onHub() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    DebugHub.instance.removeListener(_onHub);
    _scrollLog.dispose();
    _scrollConn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hub = DebugHub.instance;
    return Scaffold(
      backgroundColor: const Color(0xFF120A18),
      appBar: AppBar(
        title: const Text('Отладка'),
        actions: [
          TextButton(
            onPressed: () {
              hub.clearLogs();
              setState(() {});
            },
            child: const Text('Очистить лог'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Соединения',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: ListView.builder(
                        controller: _scrollConn,
                        padding: const EdgeInsets.all(12),
                        itemCount: hub.connections.length,
                        itemBuilder: (context, i) {
                          final c = hub.connections[i];
                          final closed = !c.isOpen;
                          final suspicious = c.suspicious;
                          final okColor = suspicious ? Colors.redAccent : Colors.lightGreenAccent;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: okColor.withValues(alpha: closed ? 0.45 : 0.95),
                                  decoration: closed ? TextDecoration.lineThrough : TextDecoration.none,
                                  decorationColor: Colors.white54,
                                ),
                                children: [
                                  TextSpan(
                                    text: suspicious ? '⚠ ' : '● ',
                                    style: TextStyle(color: okColor),
                                  ),
                                  TextSpan(text: c.label),
                                  if (c.detail != null)
                                    TextSpan(
                                      text: '\n${c.detail}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white54,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Журнал',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ListView.builder(
                        controller: _scrollLog,
                        padding: const EdgeInsets.all(12),
                        itemCount: hub.logLines.length,
                        itemBuilder: (context, i) {
                          final line = hub.logLines[hub.logLines.length - 1 - i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              line,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Colors.white70,
                                height: 1.3,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
