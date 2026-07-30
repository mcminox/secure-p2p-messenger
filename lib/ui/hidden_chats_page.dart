import 'package:flutter/material.dart';

import '../identity/user_identity.dart';
import 'widgets/app_snack.dart';
import '../p2p/internet_p2p_hub.dart';
import '../p2p/lan_p2p_controller.dart';
import '../sync/chat_index.dart';
import '../sync/local_chat_store.dart';
import 'chat_thread_page.dart';

class HiddenChatsPage extends StatelessWidget {
  const HiddenChatsPage({
    super.key,
    required this.identity,
    required this.store,
    required this.p2p,
    required this.internet,
    required this.hiddenEntries,
  });

  final UserIdentity identity;
  final LocalChatStore store;
  final LanP2pController p2p;
  final InternetP2pHub internet;
  final List<ChatListEntry> hiddenEntries;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF120A18),
      appBar: AppBar(
        title: const Text('Скрытые чаты'),
      ),
      body: hiddenEntries.isEmpty
          ? const Center(child: Text('Нет скрытых чатов'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: hiddenEntries.length,
              itemBuilder: (context, i) {
                final e = hiddenEntries[i];
                final pinned = e.userPinnedHidden;
                return Card(
                  color: Colors.white.withValues(alpha: 0.07),
                  child: ListTile(
                    title: Text(e.title),
                    subtitle: Text(
                      pinned
                          ? 'Скрыто вручную · долгое нажатие — вернуть в список'
                          : 'Собеседник не в сети в LAN (личный чат)',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onLongPress: pinned
                        ? () async {
                            await store.updateChatEntry(
                              e.copyWith(userPinnedHidden: false, clearHiddenAt: true),
                            );
                            if (context.mounted) {
                              AppSnack.show(context, 'Чат возвращён в основной список');
                            }
                          }
                        : null,
                    onTap: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (ctx) => ChatThreadPage(
                            identity: identity,
                            entry: e,
                            store: store,
                            p2p: p2p,
                            internet: internet,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
