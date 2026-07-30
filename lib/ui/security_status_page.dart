import 'package:flutter/material.dart';

import '../prefs/app_preferences.dart';
import 'widgets/messenger_backdrop.dart';
import 'widgets/secure_ui.dart';

class SecurityStatusPage extends StatefulWidget {
  const SecurityStatusPage({
    super.key,
    required this.prefs,
    required this.chatCount,
  });

  final AppPreferences prefs;
  final int chatCount;

  @override
  State<SecurityStatusPage> createState() => _SecurityStatusPageState();
}

class _SecurityStatusPageState extends State<SecurityStatusPage> {
  String _profile = AppPreferences.privacyStrict;
  bool _dailyReset = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await widget.prefs.privacyProfile();
    final d = await widget.prefs.isDailyResetEnabled();
    if (!mounted) return;
    setState(() {
      _profile = p;
      _dailyReset = d;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MessengerBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Security Status')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SecureSectionTitle(
              'Текущая защита профиля',
              subtitle: 'Сводка активных правил приватности и политики синхронизации',
            ),
            const SizedBox(height: 12),
            SecureCard(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Профиль приватности'),
                    subtitle: Text(_profile),
                    leading: const Icon(Icons.privacy_tip_outlined),
                  ),
                  ListTile(
                    title: const Text('Суточный reset direct'),
                    subtitle: Text(_dailyReset ? 'включён' : 'выключен'),
                    leading: const Icon(Icons.schedule_outlined),
                  ),
                  ListTile(
                    title: const Text('Всего чатов'),
                    subtitle: Text('${widget.chatCount}'),
                    leading: const Icon(Icons.forum_outlined),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const SecureCard(
              child: Text(
                'Подсказка: перед включением доверия в direct-чате проверяйте safety code.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
