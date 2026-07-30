import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../crypto/conversation_crypto.dart';
import '../crypto/public_key_codec.dart';
import '../identity/user_identity.dart';
import '../p2p/internet_p2p_hub.dart';
import '../p2p/lan_p2p_controller.dart';
import '../prefs/app_preferences.dart';
import '../profile/avatar_store.dart';
import '../security/security_audit_log.dart';
import '../sync/chat_index.dart';
import '../sync/conversation_id.dart';
import '../sync/local_chat_store.dart';
import '../sync/models.dart';
import 'internet_connect_sheet.dart';
import 'safety_loading_screen.dart';
import 'widgets/app_snack.dart';
import 'widgets/messenger_backdrop.dart';
import 'widgets/secure_ui.dart';

class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({
    super.key,
    required this.identity,
    required this.entry,
    required this.store,
    required this.p2p,
    required this.internet,
    this.autoOpenInternetConnect = false,
  });

  final UserIdentity identity;
  final ChatListEntry entry;
  final LocalChatStore store;
  final LanP2pController p2p;
  final InternetP2pHub internet;
  final bool autoOpenInternetConnect;

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final _input = TextEditingController();
  final _searchCtl = TextEditingController();
  final _listCtl = ScrollController();
  late ChatListEntry _entry;
  ConversationSyncState? _state;
  List<ChatMessageRecord> _messages = [];
  Map<String, String> _labels = {};
  String _myFingerprint = '';
  bool _loading = true;
  bool _offlineWarned = false;
  String? _error;
  final _prefs = AppPreferences();
  String? _pinnedLogicalId;
  String? _filterMode;
  String _searchQuery = '';
  final Map<String, String> _reactions = {};
  String? _peerAvatarPath;
  bool _notificationsEnabledForChat = true;
  bool _autoOfferUsed = false;

  String? get _directPeerFingerprint {
    if (_entry.type != ChatType.direct) return null;
    final pk = parseEd25519PublicKeyHex(_entry.peerPublicKeyHex ?? '');
    return pk == null ? null : ConversationId.fingerprint(pk);
  }

  @override
  void dispose() {
    widget.p2p.removeListener(_onP2p);
    widget.internet.removeListener(_onInet);
    _input.dispose();
    _searchCtl.dispose();
    _listCtl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    widget.p2p.addListener(_onP2p);
    widget.internet.addListener(_onInet);
    _bootstrap();
    if (widget.autoOpenInternetConnect && widget.entry.type == ChatType.direct) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _openInternetSheet();
      });
    }
  }

  void _onInet() {
    if (!mounted) return;
    if (_entry.type == ChatType.direct && !widget.p2p.isDirectChatVisible(_entry) && !_offlineWarned) {
      _offlineWarned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnack.show(context, 'Собеседник временно офлайн. Чат остаётся открыт, можно поднять WebRTC.');
      });
    } else if (_entry.type == ChatType.direct && widget.p2p.isDirectChatVisible(_entry)) {
      _offlineWarned = false;
    }
    setState(() {});
    unawaited(_reloadMessages());
  }

  Future<void> _openInternetSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InternetConnectSheet(
        conversationId: _entry.conversationId,
        hub: widget.internet,
        autoStartOffer: !_autoOfferUsed && widget.autoOpenInternetConnect && _entry.type == ChatType.direct,
      ),
    );
    _autoOfferUsed = true;
    if (mounted) setState(() {});
  }

  Future<void> _refreshEntry() async {
    final list = await widget.store.loadChatEntries();
    final i = list.indexWhere((e) => e.conversationId == _entry.conversationId);
    if (i >= 0 && mounted) {
      final updated = list[i];
      String? peerPath;
      if (updated.type == ChatType.direct) {
        final pk = parseEd25519PublicKeyHex(updated.peerPublicKeyHex ?? '');
        if (pk != null) {
          peerPath = await AvatarStore.instance.peerAvatarPathOrNull(ConversationId.fingerprint(pk));
        }
      }
      setState(() {
        _entry = updated;
        _peerAvatarPath = peerPath;
      });
    }
    _pinnedLogicalId = await _prefs.pinnedMessageId(_entry.conversationId);
    _notificationsEnabledForChat =
        await _prefs.notificationsEnabledForConversation(_entry.conversationId);
  }

  void _onP2p() {
    if (!mounted) return;
    if (_entry.type == ChatType.direct && !widget.p2p.isDirectChatVisible(_entry) && !_offlineWarned) {
      _offlineWarned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnack.show(context, 'Собеседник не в LAN. Чат не закрывается, подключайте интернет-канал.');
      });
    } else if (_entry.type == ChatType.direct && widget.p2p.isDirectChatVisible(_entry)) {
      _offlineWarned = false;
    }
    setState(() {});
    unawaited(_reloadMessages());
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _pinnedLogicalId = await _prefs.pinnedMessageId(_entry.conversationId);
      _notificationsEnabledForChat =
          await _prefs.notificationsEnabledForConversation(_entry.conversationId);
      final myPub = await widget.identity.ed25519PublicKey();
      final myFp = ConversationId.fingerprint(myPub);
      final labels = <String, String>{myFp: 'Вы'};

      if (_entry.type == ChatType.direct) {
        final hex = _entry.peerPublicKeyHex;
        if (hex == null) throw StateError('Нет ключа собеседника');
        final peer = parseEd25519PublicKeyHex(hex);
        if (peer == null) throw StateError('Неверный ключ в базе');
        labels[ConversationId.fingerprint(peer)] = _entry.title;
        final peerPath = await AvatarStore.instance.peerAvatarPathOrNull(ConversationId.fingerprint(peer));
        final st = await widget.store.openConversation(
          myEd25519: myPub,
          peerEd25519: peer,
          displayTitle: _entry.title,
          peerPublicKeyHex: hex,
          peerX25519PublicHex: _entry.peerX25519PublicHex,
          trustIncomingSync: _entry.trustIncomingSync,
        );
        final msg = await widget.store.loadMessages(st.conversationId);
        if (mounted) {
          setState(() {
            _state = st;
            _messages = msg;
            _labels = labels;
            _myFingerprint = myFp;
            _peerAvatarPath = peerPath;
            _loading = false;
          });
        }
      } else {
        final st = await widget.store.loadState(_entry.conversationId);
        final msg = await widget.store.loadMessages(st.conversationId);
        for (final m in _entry.members ?? []) {
          final pk = parseEd25519PublicKeyHex(m.publicKeyHex);
          if (pk != null) {
            labels[ConversationId.fingerprint(pk)] = m.displayName;
          }
        }
        if (mounted) {
          setState(() {
            _state = st;
            _messages = msg;
            _labels = labels;
            _myFingerprint = myFp;
            _loading = false;
          });
        }
      }
      await _refreshEntry();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _reloadMessages() async {
    if (_state == null) return;
    try {
      final st = await widget.store.loadState(_state!.conversationId);
      final m = await widget.store.loadMessages(st.conversationId);
      for (final msg in m) {
        final key = '${st.conversationId}:${msg.logicalId}';
        _reactions[msg.logicalId] = await _prefs.reactionForMessage(key) ?? '';
      }
      if (mounted) {
        setState(() {
          _state = st;
          _messages = m;
        });
      }
    } catch (_) {}
  }

  String _bubbleText(String body) {
    final t = body.trimLeft();
    if (!t.startsWith('{')) return body;
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['k'] == 'att') {
        final name = j['name'] as String? ?? 'файл';
        final sz = (j['size'] as num?)?.toInt();
        final sha = j['sha256'] as String? ?? '';
        final szStr = sz != null ? ' · ${(sz / 1024).toStringAsFixed(1)} КБ' : '';
        final shortSha = sha.length > 12 ? '${sha.substring(0, 12)}…' : sha;
        return '📎 $name$szStr\nSHA-256: $shortSha';
      }
    } catch (_) {}
    return body;
  }

  Future<void> _pickAttachment() async {
    if (_state == null) return;
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) AppSnack.show(context, 'Не удалось прочитать файл');
      return;
    }
    final hash = await Sha256().hash(bytes);
    final shaHex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final dest = await widget.store.attachmentFile(shaHex);
    await File(dest.path).writeAsBytes(bytes);
    final body = jsonEncode({
      'k': 'att',
      'name': f.name,
      'sha256': shaHex,
      'size': bytes.length,
    });
    final myPub = await widget.identity.ed25519PublicKey();
    final myFp = ConversationId.fingerprint(myPub);
    (ChatMessageRecord, ConversationSyncState, Map<String, dynamic>) triple;
    try {
      triple = await widget.store.appendOutbound(
        state: _state!,
        myFingerprint: myFp,
        body: body,
      );
    } catch (e) {
      if (mounted) AppSnack.show(context, '$e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _state = triple.$2;
      _messages = [..._messages, triple.$1];
    });
    await widget.store.updateEntryPreview(_state!.conversationId, '📎 ${f.name}');
    if (_entry.type == ChatType.group) {
      await widget.p2p.multicastGroupPush(_state!.conversationId, [triple.$3]);
    } else {
      await widget.internet.requestImmediateSync(_state!.conversationId);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _state == null) return;
    final myPub = await widget.identity.ed25519PublicKey();
    final myFp = ConversationId.fingerprint(myPub);
    (ChatMessageRecord, ConversationSyncState, Map<String, dynamic>) triple;
    try {
      triple = await widget.store.appendOutbound(
        state: _state!,
        myFingerprint: myFp,
        body: text,
      );
    } catch (e) {
      if (mounted) AppSnack.show(context, '$e');
      return;
    }
    _input.clear();
    if (!mounted) return;
    setState(() {
      _state = triple.$2;
      _messages = [..._messages, triple.$1];
    });
    final preview = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    await widget.store.updateEntryPreview(_state!.conversationId, preview);
    if (_entry.type == ChatType.group) {
      await widget.p2p.multicastGroupPush(_state!.conversationId, [triple.$3]);
    } else {
      await widget.internet.requestImmediateSync(_state!.conversationId);
    }
  }

  Future<void> _showSafety() async {
    if (_entry.type != ChatType.direct) return;
    final hex = _entry.peerPublicKeyHex;
    if (hex == null) return;
    final peer = parseEd25519PublicKeyHex(hex);
    if (peer == null) return;
    final myPub = await widget.identity.ed25519PublicKey();
    final lines = await ConversationCrypto.safetyNumberLines(myPub, peer);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Код безопасности'),
        content: SelectableText(lines, style: const TextStyle(fontFamily: 'monospace')),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: lines));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Копировать'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Future<void> _showTrustCard() async {
    if (_entry.type != ChatType.direct) return;
    final hex = _entry.peerPublicKeyHex;
    final peer = parseEd25519PublicKeyHex(hex ?? '');
    if (peer == null) return;
    final myPub = await widget.identity.ed25519PublicKey();
    final safety = await ConversationCrypto.safetyNumberLines(myPub, peer);
    final checkedAt = await _prefs.trustCheckedAt(_entry.conversationId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Карточка доверия'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Контакт: ${_entry.title}'),
            const SizedBox(height: 8),
            SelectableText(safety, style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 8),
            Text(checkedAt == null ? 'Проверка: не подтверждена' : 'Проверка: $checkedAt UTC'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Future<void> _setReaction(String logicalId, String? emoji) async {
    final key = '${_entry.conversationId}:$logicalId';
    await _prefs.setReactionForMessage(key, emoji);
    if (!mounted) return;
    setState(() {
      _reactions[logicalId] = emoji ?? '';
    });
  }

  Future<void> _setPinned(String? logicalId) async {
    await _prefs.setPinnedMessageId(_entry.conversationId, logicalId);
    if (!mounted) return;
    setState(() {
      _pinnedLogicalId = logicalId;
    });
  }

  Future<void> _toggleNotificationsForChat(bool enabled) async {
    await _prefs.setNotificationsEnabledForConversation(_entry.conversationId, enabled);
    if (!mounted) return;
    setState(() {
      _notificationsEnabledForChat = enabled;
    });
    AppSnack.show(context, enabled ? 'Уведомления для чата включены' : 'Уведомления для чата выключены');
  }

  Future<void> _messageActions(ChatMessageRecord m) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1524),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: const Text('Реакция'),
              subtitle: const Text('👍 ❤️ 😂 🔥 😮 😢'),
              onTap: () => Navigator.pop(ctx, 'react'),
            ),
            ListTile(
              title: Text(_pinnedLogicalId == m.logicalId ? 'Открепить' : 'Закрепить'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'react') {
      final pick = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Быстрая реакция'),
          content: Wrap(
            spacing: 8,
            children: ['👍', '❤️', '😂', '🔥', '😮', '😢']
                .map((e) => ActionChip(label: Text(e), onPressed: () => Navigator.pop(ctx, e)))
                .toList(),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Убрать'))],
        ),
      );
      if (pick != null) {
        await _setReaction(m.logicalId, pick.isEmpty ? null : pick);
      }
    } else if (choice == 'pin') {
      await _setPinned(_pinnedLogicalId == m.logicalId ? null : m.logicalId);
    }
  }

  Future<void> _pickChatColor() async {
    final options = <int>[
      Colors.redAccent.value,
      Colors.orangeAccent.value,
      Colors.amber.value,
      Colors.lightGreenAccent.value,
      Colors.cyanAccent.value,
      Colors.blueAccent.value,
      Colors.purpleAccent.value,
    ];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Цветовая метка чата'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ...options.map(
              (c) => GestureDetector(
                onTap: () => Navigator.pop(ctx, c),
                child: CircleAvatar(backgroundColor: Color(c), radius: 16),
              ),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: const Text('Сбросить'),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _prefs.setChatColor(_entry.conversationId, picked == 0 ? null : picked);
    if (mounted) AppSnack.show(context, picked == 0 ? 'Метка снята' : 'Метка сохранена');
  }

  void _jumpToPinned() {
    if (_pinnedLogicalId == null) {
      if (mounted) AppSnack.show(context, 'Нет закрепленного сообщения');
      return;
    }
    setState(() {
      _filterMode = 'important';
    });
    _listCtl.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _toggleTrust(bool v) async {
    if (_entry.type == ChatType.group) {
      if (mounted) AppSnack.show(context, 'Для групп доверие к синхронизации включено автоматически.');
      return;
    }
    if (v) {
      final hex = _entry.peerPublicKeyHex;
      final peer = parseEd25519PublicKeyHex(hex ?? '');
      final myPub = await widget.identity.ed25519PublicKey();
      if (peer == null) {
        if (mounted) AppSnack.show(context, 'Невозможно выполнить safety check: ключ собеседника повреждён.');
        return;
      }
      final lines = await ConversationCrypto.safetyNumberLines(myPub, peer);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Safety check'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Подтвердите код безопасности перед разрешением синхронизации:'),
              const SizedBox(height: 10),
              SelectableText(lines, style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Подтвердить')),
          ],
        ),
      );
      if (confirmed != true) return;
      await _prefs.markTrustCheckedNow(_entry.conversationId);
      await SecurityAuditLog.instance.append(
        'safety_check_confirmed',
        details: {'conversation_id': _entry.conversationId},
      );
    }
    await widget.store.updateChatEntry(_entry.copyWith(trustIncomingSync: v));
    await SecurityAuditLog.instance.append(
      'sync_trust_changed',
      details: {
        'conversation_id': _entry.conversationId,
        'enabled': v,
      },
    );
    await _refreshEntry();
    if (mounted) {
      AppSnack.show(
        context,
        v ? 'Входящая синхронизация разрешена' : 'Входящая синхронизация отключена',
      );
    }
  }

  Future<void> _hideChat() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await widget.store.updateChatEntry(
      _entry.copyWith(userPinnedHidden: true, hiddenAtMillis: now),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: const Text('Сообщения и ключи переписки на этом устройстве будут удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await widget.store.deleteConversation(_entry.conversationId);
      widget.p2p.invalidateInterestCache();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _editGroupMembers() async {
    if (_entry.type != ChatType.group) return;
    final rows = <_EditableMemberRow>[];
    for (final m in _entry.members ?? const <GroupMemberEntry>[]) {
      rows.add(_EditableMemberRow(name: m.displayName, edHex: m.publicKeyHex, xHex: m.x25519PublicKeyHex ?? ''));
    }
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Участники группы'),
        content: SizedBox(
          width: 560,
          child: StatefulBuilder(
            builder: (context, setModal) => Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...rows.asMap().entries.map((e) {
                      final i = e.key;
                      final row = e.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: row.name,
                                    decoration: InputDecoration(labelText: 'Имя ${i + 1}'),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Имя' : null,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => setModal(() => rows.removeAt(i)),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: row.edHex,
                              decoration: const InputDecoration(labelText: 'Ed25519 hex'),
                              validator: (v) => parseEd25519PublicKeyHex(v ?? '') == null ? '64 hex' : null,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: row.xHex,
                              decoration: const InputDecoration(labelText: 'X25519 hex'),
                              validator: (v) => parseX25519PublicKeyHex(v ?? '') == null ? '64 hex' : null,
                            ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: () => setModal(() => rows.add(_EditableMemberRow())),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      for (final r in rows) {
        r.dispose();
      }
      return;
    }
    final members = <GroupMemberEntry>[];
    final myEd = await widget.identity.ed25519PublicKey();
    final myX = await widget.identity.x25519PublicKey();
    var hasMe = false;
    for (final r in rows) {
      final name = r.name.text.trim();
      final ed = r.edHex.text.trim().replaceAll(RegExp(r'\s'), '').toLowerCase();
      final x = r.xHex.text.trim().replaceAll(RegExp(r'\s'), '').toLowerCase();
      final edPk = parseEd25519PublicKeyHex(ed);
      final xPk = parseX25519PublicKeyHex(x);
      if (name.isEmpty || edPk == null || xPk == null) continue;
      if (ed25519PublicKeysEqual(edPk, myEd)) hasMe = true;
      members.add(GroupMemberEntry(displayName: name, publicKeyHex: ed, x25519PublicKeyHex: x));
    }
    if (!hasMe) {
      members.insert(
        0,
        GroupMemberEntry(
          displayName: 'Вы',
          publicKeyHex: ed25519PublicKeyToHex(myEd),
          x25519PublicKeyHex: x25519PublicKeyToHex(myX),
        ),
      );
    }
    await widget.store.updateChatEntry(_entry.copyWith(members: members));
    await _refreshEntry();
    if (mounted) {
      AppSnack.show(
        context,
        'Состав группы обновлён. Участникам нужно синхронизироваться, чтобы получить новый ключ.',
      );
    }
    for (final r in rows) {
      r.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final peerFp = _directPeerFingerprint;
    final lanOnline = peerFp != null && widget.p2p.isPeerOnline(peerFp);
    final inetOnline = widget.internet.isLinked(_entry.conversationId);
    final peerOnline = lanOnline || inetOnline;

    return MessengerBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.25),
          surfaceTintColor: Colors.transparent,
          leadingWidth: _entry.type == ChatType.direct ? 56 : null,
          leading: _entry.type == ChatType.direct
              ? Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primary.withValues(alpha: 0.35),
                    backgroundImage: _peerAvatarPath == null ? null : FileImage(File(_peerAvatarPath!)),
                    child: _peerAvatarPath == null ? const Icon(Icons.person_rounded, size: 16) : null,
                  ),
                )
              : null,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_entry.title),
              if (_entry.type == ChatType.direct)
                Text(
                  inetOnline
                      ? 'в сети · интернет'
                      : lanOnline
                          ? 'в сети · LAN'
                          : 'не в сети',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: peerOnline ? Colors.lightGreenAccent : Colors.white54,
                  ),
                ),
            ],
          ),
          actions: [
            if (_entry.type == ChatType.direct)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Center(
                  child: SecureBadge(label: 'E2E', icon: Icons.lock_rounded),
                ),
              ),
            if (_entry.type == ChatType.direct)
              IconButton(
                tooltip: 'Интернет (WebRTC)',
                onPressed: _openInternetSheet,
                icon: Icon(
                  inetOnline ? Icons.public_rounded : Icons.public_outlined,
                  color: inetOnline ? Colors.lightGreenAccent : null,
                ),
              ),
            if (_entry.type == ChatType.group)
              Icon(Icons.groups_rounded, color: cs.primary.withValues(alpha: 0.9)),
            IconButton(
              tooltip: 'К закреплённому',
              onPressed: _jumpToPinned,
              icon: const Icon(Icons.push_pin_outlined),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) async {
                switch (v) {
                  case 'internet':
                    await _openInternetSheet();
                    break;
                  case 'members':
                    await _editGroupMembers();
                    break;
                  case 'safety':
                    await _showSafety();
                    break;
                  case 'trust_card':
                    await _showTrustCard();
                    break;
                  case 'filter_all':
                    setState(() => _filterMode = null);
                    break;
                  case 'filter_important':
                    setState(() => _filterMode = 'important');
                    break;
                  case 'filter_mine':
                    setState(() => _filterMode = 'mine');
                    break;
                  case 'filter_attach':
                    setState(() => _filterMode = 'attach');
                    break;
                  case 'chat_color':
                    await _pickChatColor();
                    break;
                  case 'notif_on':
                    await _toggleNotificationsForChat(true);
                    break;
                  case 'notif_off':
                    await _toggleNotificationsForChat(false);
                    break;
                  case 'trust_on':
                    await _toggleTrust(true);
                    break;
                  case 'trust_off':
                    await _toggleTrust(false);
                    break;
                  case 'hide':
                    await _hideChat();
                    break;
                  case 'delete':
                    await _deleteChat();
                    break;
                }
              },
              itemBuilder: (ctx) => [
                if (_entry.type == ChatType.direct)
                  const PopupMenuItem(value: 'internet', child: Text('Интернет-связь (WebRTC)')),
                if (_entry.type == ChatType.group)
                  const PopupMenuItem(value: 'members', child: Text('Участники группы')),
                if (_entry.type == ChatType.direct)
                  const PopupMenuItem(value: 'safety', child: Text('Код безопасности')),
                if (_entry.type == ChatType.direct)
                  const PopupMenuItem(value: 'trust_card', child: Text('Карточка доверия')),
                const PopupMenuItem(value: 'filter_all', child: Text('Фильтр: все')),
                const PopupMenuItem(value: 'filter_important', child: Text('Фильтр: важное')),
                const PopupMenuItem(value: 'filter_mine', child: Text('Фильтр: только мои')),
                const PopupMenuItem(value: 'filter_attach', child: Text('Фильтр: вложения')),
                const PopupMenuItem(value: 'chat_color', child: Text('Цветовая метка чата')),
                if (_notificationsEnabledForChat)
                  const PopupMenuItem(value: 'notif_off', child: Text('Выключить уведомления чата'))
                else
                  const PopupMenuItem(value: 'notif_on', child: Text('Включить уведомления чата')),
                if (_entry.type == ChatType.direct)
                  if (_entry.trustIncomingSync)
                    const PopupMenuItem(value: 'trust_off', child: Text('Отключить доверие к синхронизации'))
                  else
                    const PopupMenuItem(value: 'trust_on', child: Text('Доверять входящей синхронизации')),
                const PopupMenuItem(value: 'hide', child: Text('Скрыть чат')),
                const PopupMenuItem(value: 'delete', child: Text('Удалить чат')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _loading
              ? const SafetyLoadingScreen(message: 'Открываем чат…')
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: TextField(
                            controller: _searchCtl,
                            onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Поиск по чату',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close_rounded),
                                      onPressed: () {
                                        _searchCtl.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    ),
                            ),
                          ),
                        ),
                        if (_entry.type == ChatType.direct)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 88, 12, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_entry.peerX25519PublicHex == null ||
                                    _entry.peerX25519PublicHex!.isEmpty)
                                  SecureCard(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Text(
                                        'Без ключа X25519 текст на диске привязан к сессии устройства. Для общего E2E передайте друг другу ключи X25519.',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                  ),
                                if (!_entry.trustIncomingSync) ...[
                                  const SizedBox(height: 8),
                                  SecureCard(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Text(
                                        'Входящая синхронизация отключена. После суточного сброса включайте её вручную в меню чата, когда нужно подтянуть сообщения.',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                  ),
                                ],
                                if (peerFp != null && !peerOnline) ...[
                                  if (_entry.peerX25519PublicHex == null ||
                                      _entry.peerX25519PublicHex!.isEmpty)
                                    const SizedBox(height: 8),
                                  SecureCard(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Text(
                                        'Нет LAN и нет интернет-канала. Откройте «Интернет (WebRTC)» в шапке или дождитесь одной Wi‑Fi.',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final filtered = _messages.where((m) {
                                final rendered = _bubbleText(m.body).toLowerCase();
                                if (_searchQuery.isNotEmpty && !rendered.contains(_searchQuery)) {
                                  return false;
                                }
                                if (_filterMode == null) return true;
                                if (_filterMode == 'mine') return m.senderFingerprint == _myFingerprint;
                                if (_filterMode == 'attach') return _bubbleText(m.body).startsWith('📎');
                                if (_filterMode == 'important') {
                                  return m.logicalId == _pinnedLogicalId || _reactions[m.logicalId]?.isNotEmpty == true;
                                }
                                return true;
                              }).toList();
                              ChatMessageRecord? pinned;
                              if (_pinnedLogicalId != null) {
                                for (final m in _messages) {
                                  if (m.logicalId == _pinnedLogicalId) {
                                    pinned = m;
                                    break;
                                  }
                                }
                              }
                              return Column(
                                children: [
                                  if (pinned != null)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                                      child: Material(
                                        color: Colors.blueGrey.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(10),
                                        child: ListTile(
                                          dense: true,
                                          title: const Text('Закреплённое'),
                                          subtitle: Text(_bubbleText(pinned.body), maxLines: 2, overflow: TextOverflow.ellipsis),
                                          trailing: IconButton(
                                            icon: const Icon(Icons.close_rounded),
                                            onPressed: () => _setPinned(null),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: filtered.isEmpty
                              ? Center(
                                  child: Text(
                                    'Нет сообщений.\nВ одной Wi‑Fi или через интернет-канал (иконка глобуса) история подтянется при включённом доверии к синхронизации.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Colors.white60,
                                        ),
                                  ).animate().fade(duration: 400.ms),
                                )
                              : ListView.builder(
                                  controller: _listCtl,
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) {
                                    final m = filtered[i];
                                    final isMine = m.senderFingerprint == _myFingerprint;
                                    final who = _labels[m.senderFingerprint] ?? m.senderFingerprint;
                                    final shown = _bubbleText(m.body);
                                    final reaction = _reactions[m.logicalId] ?? '';
                                    final status = isMine
                                        ? (_entry.type == ChatType.group
                                            ? 'group'
                                            : (_entry.trustIncomingSync ? 'sync:on' : 'sync:off'))
                                        : '';
                                    return Align(
                                      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                                          ),
                                          child: Material(
                                            color: isMine
                                                ? cs.primary.withValues(alpha: 0.35)
                                                : Colors.white.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(18),
                                              topRight: const Radius.circular(18),
                                              bottomLeft: Radius.circular(isMine ? 18 : 4),
                                              bottomRight: Radius.circular(isMine ? 4 : 18),
                                            ),
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(18),
                                              onLongPress: () => _messageActions(m),
                                              child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (!isMine || _entry.type == ChatType.group)
                                                    Text(
                                                      who,
                                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                            color: cs.secondary,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                    ),
                                                  if (!isMine || _entry.type == ChatType.group)
                                                    const SizedBox(height: 4),
                                                  Text(
                                                    shown,
                                                    style: Theme.of(context).textTheme.bodyMedium,
                                                  ),
                                                  if (reaction.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(reaction, style: const TextStyle(fontSize: 16)),
                                                  ],
                                                  if (status.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(status, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54)),
                                                  ],
                                                ],
                                              ),
                                            )),
                                          ),
                                        ),
                                      ),
                                    )
                                        .animate(key: ValueKey(m.logicalId))
                                        .fadeIn(duration: 220.ms)
                                        .slideY(begin: 0.06, curve: Curves.easeOutCubic);
                                  },
                                ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton.filledTonal(
                                onPressed: _pickAttachment,
                                icon: const Icon(Icons.attach_file_rounded),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: TextField(
                                  controller: _input,
                                  minLines: 1,
                                  maxLines: 5,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(),
                                  decoration: const InputDecoration(
                                    hintText: 'Сообщение…',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _send,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.all(14),
                                  shape: const CircleBorder(),
                                ),
                                child: const Icon(Icons.send_rounded, size: 22),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

}

class _EditableMemberRow {
  _EditableMemberRow({
    String? name,
    String? edHex,
    String? xHex,
  })  : name = TextEditingController(text: name ?? ''),
        edHex = TextEditingController(text: edHex ?? ''),
        xHex = TextEditingController(text: xHex ?? '');

  final TextEditingController name;
  final TextEditingController edHex;
  final TextEditingController xHex;

  void dispose() {
    name.dispose();
    edHex.dispose();
    xHex.dispose();
  }
}
