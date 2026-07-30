import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';

import '../auth/secure_app_repository.dart';
import '../crypto/public_key_codec.dart';
import '../identity/rotating_peer_id.dart';
import '../identity/user_identity.dart';
import '../invite/invite_codec.dart';
import '../p2p/internet_p2p_hub.dart';
import '../p2p/lan_p2p_controller.dart';
import '../p2p/rtc_signaling_codec.dart';
import '../prefs/app_preferences.dart';
import '../profile/avatar_store.dart';
import '../security/security_audit_log.dart';
import '../security/license_guard.dart';
import '../sync/chat_index.dart';
import '../sync/conversation_id.dart';
import '../sync/local_chat_store.dart';
import '../util/webrtc_deeplink_bridge.dart';
import 'app_settings_page.dart';
import 'chat_thread_page.dart';
import 'debug_console_page.dart';
import 'hidden_chats_page.dart';
import 'invite_hub_sheet.dart';
import 'security_journal_page.dart';
import 'security_status_page.dart';
import 'widgets/app_snack.dart';
import 'widgets/messenger_backdrop.dart';
import 'widgets/secure_ui.dart';

class MessengerHomePage extends StatefulWidget {
  const MessengerHomePage({
    super.key,
    required this.identity,
    required this.repository,
    required this.onLock,
    required this.onPanicLock,
    required this.onWipeAllData,
  });

  final UserIdentity identity;
  final SecureAppRepository repository;
  final VoidCallback onLock;
  final Future<void> Function() onPanicLock;
  final Future<void> Function() onWipeAllData;

  @override
  State<MessengerHomePage> createState() => _MessengerHomePageState();
}

class _MessengerHomePageState extends State<MessengerHomePage> {
  late final LocalChatStore _store;
  late final LanP2pController _p2p;
  late final InternetP2pHub _internetHub;
  final _licenseGuard = LicenseGuard();
  List<ChatListEntry> _chats = [];
  RotatingPeerId? _rotating;
  String _peerIdDisplay = '…';
  String _myPublicHex = '…';
  String _myX25519Hex = '…';
  Timer? _tick;
  final _prefs = AppPreferences();
  bool _showEd25519 = false;
  bool _showX25519 = false;
  bool _keysExpanded = false;
  Timer? _dailyPolicyTimer;
  final Map<String, int> _chatColors = {};
  String? _myAvatarPath;
  final Map<String, String> _peerAvatarPathByConversation = {};

  @override
  void initState() {
    super.initState();
    _store = LocalChatStore(identity: widget.identity, repository: widget.repository);
    _p2p = LanP2pController(identity: widget.identity, store: _store);
    _internetHub = InternetP2pHub(
      identity: widget.identity,
      store: _store,
      allowSecureSync: _licenseGuard.canAccessSecureFlows,
    );
    _p2p.internetLinked = _internetHub.isLinked;
    _p2p.addListener(_onP2p);
    _internetHub.addListener(_onP2p);
    _bootstrap();
  }

  void _onP2p() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    final rot = RotatingPeerId(
      window: RotatingPeerId.defaultWindow(),
    );
    final edPub = await widget.identity.ed25519PublicKey();
    final xPub = await widget.identity.x25519PublicKey();
    rot.updatePublicKeys(
      ed25519Public: Uint8List.fromList(edPub.bytes),
      x25519Public: Uint8List.fromList(xPub.bytes),
    );
    final hex = ed25519PublicKeyToHex(edPub);
    final xHex = x25519PublicKeyToHex(xPub);
    await _prefs.setDevicePubkey(xHex);
    setState(() {
      _rotating = rot;
      _myPublicHex = hex;
      _myX25519Hex = xHex;
    });
    await _refreshPeerId();
    await _maybeShowOnboarding();
    await _applyDailyPrivacyPolicyIfNeeded();
    await _loadChats();
    await _p2p.start();
    if (mounted && !_p2p.isRunning) {
      AppSnack.show(
        context,
        'Не удалось открыть LAN-UDP (порт 52525). Проверьте разрешения и что порт свободен.',
      );
    }
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _refreshPeerId());
    _dailyPolicyTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _applyDailyPrivacyPolicyIfNeeded(),
    );
  }

  Future<void> _applyDailyPrivacyPolicyIfNeeded() async {
    if (!await _prefs.isDailyResetEnabled()) return;
    final needed = await _prefs.shouldApplyDailyPrivacyPolicy();
    if (!needed) return;
    final changed = await _store.enforceDailyDirectResetAndGroupAutoTrust();
    await _prefs.markDailyPrivacyPolicyAppliedNow();
    await _loadChats();
    if (mounted && changed > 0) {
      AppSnack.show(
        context,
        'Суточная защита: удалены чужие сообщения в личных чатах. Для синхронизации нужно заново разрешить доступ.',
      );
    }
  }

  Future<void> _maybeShowOnboarding() async {
    if (await _prefs.onboardingSeen()) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Быстрый старт'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1) Добавьте контакт с Ed25519 + X25519.'),
            SizedBox(height: 6),
            Text('2) Проверьте safety code перед trust sync.'),
            SizedBox(height: 6),
            Text('3) Для интернета используйте WebRTC offer/answer.'),
            SizedBox(height: 6),
            Text('4) Включайте trust sync вручную только когда нужно.'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
    await _prefs.setOnboardingSeen(true);
  }

  Future<void> _pickPrivacyProfile() async {
    final current = await _prefs.privacyProfile();
    if (!mounted) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Профиль приватности'),
        children: [
          RadioListTile<String>(
            value: AppPreferences.privacyStandard,
            groupValue: current,
            onChanged: (v) => Navigator.pop(ctx, v),
            title: const Text('Стандарт'),
            subtitle: const Text('Без суточного сброса входящих'),
          ),
          RadioListTile<String>(
            value: AppPreferences.privacyStrict,
            groupValue: current,
            onChanged: (v) => Navigator.pop(ctx, v),
            title: const Text('Строгий'),
            subtitle: const Text('Суточный reset direct-входящих'),
          ),
          RadioListTile<String>(
            value: AppPreferences.privacyParanoid,
            groupValue: current,
            onChanged: (v) => Navigator.pop(ctx, v),
            title: const Text('Параноидальный'),
            subtitle: const Text('Строгий режим + ручной trust каждую сессию'),
          ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    await _prefs.setPrivacyProfile(picked);
    if (picked == AppPreferences.privacyParanoid) {
      await _prefs.setSendAvatarInSync(false);
    }
    if (picked != AppPreferences.privacyStandard) {
      await _applyDailyPrivacyPolicyIfNeeded();
    }
    if (mounted) {
      AppSnack.show(context, 'Профиль приватности: $picked');
    }
  }

  Future<void> _loadChats() async {
    final list = await _store.loadChatEntries();
    list.sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    final colors = <String, int>{};
    final peerPaths = <String, String>{};
    for (final e in list) {
      final c = await _prefs.chatColor(e.conversationId);
      if (c != null) colors[e.conversationId] = c;
      if (e.type == ChatType.direct) {
        final pk = parseEd25519PublicKeyHex(e.peerPublicKeyHex ?? '');
        if (pk != null) {
          final fp = ConversationId.fingerprint(pk);
          final path = await AvatarStore.instance.peerAvatarPathOrNull(fp);
          if (path != null) peerPaths[e.conversationId] = path;
        }
      }
    }
    final myAvatarPath = await AvatarStore.instance.myAvatarPathOrNull();
    if (mounted) {
      setState(() {
        _chats = list;
        _chatColors
          ..clear()
          ..addAll(colors);
        _peerAvatarPathByConversation
          ..clear()
          ..addAll(peerPaths);
        _myAvatarPath = myAvatarPath;
      });
    }
  }

  Future<void> _pickMyAvatar() async {
    final res = await FilePicker.platform.pickFiles(withData: true, type: FileType.image);
    if (res == null || res.files.isEmpty) return;
    final b = res.files.single.bytes;
    if (b == null || b.isEmpty) return;
    await AvatarStore.instance.setMyAvatarFromBytes(b);
    await _loadChats();
    if (mounted) AppSnack.show(context, 'Аватар обновлён');
  }

  Future<void> _deleteMyAvatar() async {
    await AvatarStore.instance.clearMyAvatar();
    await _loadChats();
    if (mounted) AppSnack.show(context, 'Аватар удалён');
  }

  Future<void> _toggleAvatarSync() async {
    final current = await _prefs.sendAvatarInSync();
    await _prefs.setSendAvatarInSync(!current);
    if (mounted) {
      AppSnack.show(context, !current ? 'Отправка аватара в sync включена' : 'Отправка аватара в sync отключена');
      setState(() {});
    }
  }

  Future<void> _refreshPeerId() async {
    if (_rotating == null) return;
    final v = await _rotating!.current();
    if (mounted) setState(() => _peerIdDisplay = v);
  }

  @override
  void dispose() {
    _p2p.removeListener(_onP2p);
    _internetHub.removeListener(_onP2p);
    _internetHub.dispose();
    _p2p.dispose();
    _tick?.cancel();
    _dailyPolicyTimer?.cancel();
    super.dispose();
  }

  Future<void> _confirmWipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить все данные?'),
        content: const Text(
          'Будут удалены ключи, чаты и настройки на этом устройстве.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить всё'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await widget.onWipeAllData();
  }

  Future<void> _showKeyHintSheet({required bool isEd25519}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        var skipHint = false;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1228),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFB388FF).withValues(alpha: 0.45)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isEd25519
                            ? 'Сейчас вы покажете публичный ключ Ed25519'
                            : 'Сейчас вы покажете публичный ключ X25519',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isEd25519
                            ? 'Он идентифицирует вас: по нему контакты открывают с вами чат и сверяют подписи.'
                            : 'Он нужен для общего секрета X25519 — сквозного шифрования текста с тем, кому вы его отправите.',
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.95),
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isEd25519
                            ? 'Если ключ окажется у злоумышленника, вас могут подделать в сети до смены ключей и пересоздания контактов.'
                            : 'Если потеряете или передадите не тому, конфиденциальность переписки под угрозой — придётся менять ключи и пересоздавать чаты.',
                        style: TextStyle(
                          color: Colors.pinkAccent.shade100,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Больше не спрашивать для этого ключа'),
                        value: skipHint,
                        onChanged: (v) => setModal(() => skipHint = v ?? false),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () async {
                          if (skipHint) {
                            if (isEd25519) {
                              await _prefs.setSkipHintEd25519(true);
                            } else {
                              await _prefs.setSkipHintX25519(true);
                            }
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            setState(() {
                              if (isEd25519) {
                                _showEd25519 = true;
                              } else {
                                _showX25519 = true;
                              }
                            });
                          }
                        },
                        child: const Text('Показать'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleEd25519() async {
    if (_showEd25519) {
      setState(() => _showEd25519 = false);
      return;
    }
    if (await _prefs.skipHintEd25519()) {
      setState(() => _showEd25519 = true);
      return;
    }
    await _showKeyHintSheet(isEd25519: true);
  }

  Future<void> _toggleX25519() async {
    if (_showX25519) {
      setState(() => _showX25519 = false);
      return;
    }
    if (await _prefs.skipHintX25519()) {
      setState(() => _showX25519 = true);
      return;
    }
    await _showKeyHintSheet(isEd25519: false);
  }

  Future<void> _copyEd25519() async {
    if (!_showEd25519) {
      if (await _prefs.skipHintEd25519()) {
        if (!context.mounted) return;
        setState(() => _showEd25519 = true);
      } else {
        await _showKeyHintSheet(isEd25519: true);
      }
    }
    if (!context.mounted || !_showEd25519) return;
    await Clipboard.setData(ClipboardData(text: _myPublicHex));
    if (context.mounted) {
      AppSnack.show(context, 'Публичный ключ Ed25519 скопирован');
    }
  }

  Future<void> _copyX25519() async {
    if (!_showX25519) {
      if (await _prefs.skipHintX25519()) {
        if (!context.mounted) return;
        setState(() => _showX25519 = true);
      } else {
        await _showKeyHintSheet(isEd25519: false);
      }
    }
    if (!context.mounted || !_showX25519) return;
    await Clipboard.setData(ClipboardData(text: _myX25519Hex));
    if (context.mounted) {
      AppSnack.show(context, 'Публичный ключ X25519 скопирован');
    }
  }

  Future<void> _openChat(ChatListEntry e, {bool autoOpenInternetConnect = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => ChatThreadPage(
          identity: widget.identity,
          entry: e,
          store: _store,
          p2p: _p2p,
          internet: _internetHub,
          autoOpenInternetConnect: autoOpenInternetConnect,
        ),
      ),
    );
    await _loadChats();
  }

  Future<void> _applyInvitePayload(String raw) async {
    final rtcRaw = _decodeWebrtcPayload(raw);
    if (rtcRaw != null) {
      final rtc = RtcSignalingCodec.tryParse(rtcRaw);
      if (rtc != null) {
        final chats = await _store.loadChatEntries();
        ChatListEntry? target;
        for (final e in chats) {
          if (e.conversationId == rtc.cid && e.type == ChatType.direct) {
            target = e;
            break;
          }
        }
        if (target == null) {
          if (mounted) {
            AppSnack.show(context, 'Это WebRTC-код. Сначала добавьте контакт приглашением.');
          }
          return;
        }
        WebrtcDeepLinkBridge.instance.injectLocal(rtcRaw);
        await _openChat(target, autoOpenInternetConnect: true);
        return;
      }
    }
    final m = InviteCodec.tryParse(raw);
    if (m == null) {
      if (mounted) AppSnack.show(context, 'Не удалось разобрать приглашение');
      return;
    }
    final name = m['n'] as String;
    final edHex = m['ed'] as String;
    final peer = parseEd25519PublicKeyHex(edHex);
    if (peer == null) {
      if (mounted) AppSnack.show(context, 'Неверный Ed25519 в приглашении');
      return;
    }
    final me = await widget.identity.ed25519PublicKey();
    if (ed25519PublicKeysEqual(peer, me)) {
      if (mounted) AppSnack.show(context, 'Это ваше собственное приглашение');
      return;
    }
    final xHex = m['x'] as String?;
    await _store.openConversation(
      myEd25519: me,
      peerEd25519: peer,
      displayTitle: name,
      peerPublicKeyHex: edHex,
      peerX25519PublicHex: xHex,
      trustIncomingSync: false,
    );
    if (!mounted) return;
    _p2p.invalidateInterestCache();
    await _loadChats();
    final list = await _store.loadChatEntries();
    final convId = await ConversationId.fromEd25519PublicKeys(me, peer);
    final entry = list.firstWhere((e) => e.conversationId == convId);
    await _openChat(entry, autoOpenInternetConnect: true);
  }

  String? _decodeWebrtcPayload(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final uri = Uri.tryParse(s);
    if (uri == null || uri.scheme != 'dartaut' || uri.host != 'webrtc') return null;
    final payload = uri.queryParameters['payload'];
    if (payload == null || payload.isEmpty) return null;
    try {
      final bytes = base64Url.decode(base64Url.normalize(payload));
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openInviteHub() async {
    if (_rotating == null) return;
    final connectToken = (await _prefs.connectToken()) ?? '';
    final raw = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InviteHubSheet(
        ed25519Hex: _myPublicHex,
        x25519Hex: _myX25519Hex,
        rotating: _rotating!,
        connectToken: connectToken,
      ),
    );
    if (raw != null && raw.isNotEmpty && mounted) {
      await _applyInvitePayload(raw);
    }
  }

  Future<void> _pasteInviteDialog() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Вставить приглашение'),
        content: TextField(
          controller: ctl,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'dartaut-invite:... или dartaut://webrtc?...',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Открыть')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _applyInvitePayload(ctl.text);
    }
    ctl.dispose();
  }

  Future<void> _showNewMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: const Color(0xFF1A1524),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(Icons.qr_code_2_rounded, color: cs.tertiary),
                    title: const Text('Моё приглашение (QR)'),
                    subtitle: const Text('Ключи + код сверки; скан чужого QR с телефона'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openInviteHub();
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.paste_rounded, color: cs.primary),
                    title: const Text('Вставить приглашение'),
                    subtitle: const Text('JSON из буфера или текста'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pasteInviteDialog();
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.person_add_alt_1_rounded, color: cs.primary),
                    title: const Text('Личный чат'),
                    subtitle: const Text('По публичному ключу Ed25519 собеседника'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showNewDirect();
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.groups_rounded, color: cs.secondary),
                    title: const Text('Группа'),
                    subtitle: const Text('Название и ключи участников'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showNewGroup();
                    },
                  ),
                ],
              ),
            ),
          ),
        ).animate().slideY(begin: 0.08, curve: Curves.easeOutCubic).fadeIn();
      },
    );
  }

  Future<void> _showNewDirect() async {
    final nameCtl = TextEditingController();
    final keyCtl = TextEditingController();
    final x25519Ctl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var trustLan = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.82,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
                  return Material(
                    color: const Color(0xFF1A1524),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Form(
                        key: formKey,
                        child: ListView(
                          controller: scrollController,
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Text(
                              'Новый личный чат',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ed25519 — идентичность; X25519 — общий секрет для E2E текста (попросите у контакта отдельно).',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: nameCtl,
                              decoration: const InputDecoration(
                                labelText: 'Имя в списке',
                                hintText: 'Например, Анна',
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: keyCtl,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Публичный ключ Ed25519 (hex)',
                                alignLabelWithHint: true,
                              ),
                              validator: (v) {
                                if (parseEd25519PublicKeyHex(v ?? '') == null) {
                                  return 'Нужно ровно 64 hex-символа';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: x25519Ctl,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Публичный ключ X25519 (hex), необязательно',
                                alignLabelWithHint: true,
                              ),
                              validator: (v) {
                                final s = v?.trim() ?? '';
                                if (s.isEmpty) return null;
                                if (parseX25519PublicKeyHex(s) == null) {
                                  return '64 hex-символа или оставьте пустым';
                                }
                                return null;
                              },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Доверять входящей синхронизации'),
                              subtitle: Text(
                                'Разрешить контакту забирать ваши сообщения в одной Wi‑Fi',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
                              ),
                              value: trustLan,
                              onChanged: (v) => setModal(() => trustLan = v),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () async {
                                if (!(formKey.currentState?.validate() ?? false)) return;
                                final peer = parseEd25519PublicKeyHex(keyCtl.text)!;
                                final me = await widget.identity.ed25519PublicKey();
                                if (ed25519PublicKeysEqual(peer, me)) {
                                  if (context.mounted) {
                                AppSnack.show(context, 'Это ваш собственный ключ');
                                  }
                                  return;
                                }
                                final title = nameCtl.text.trim();
                                final hex = keyCtl.text.trim().replaceAll(RegExp(r'\s'), '').toLowerCase();
                                final xRaw = x25519Ctl.text.trim().replaceAll(RegExp(r'\s'), '').toLowerCase();
                                final xHex = xRaw.isEmpty ? null : xRaw;
                                await _store.openConversation(
                                  myEd25519: me,
                                  peerEd25519: peer,
                                  displayTitle: title,
                                  peerPublicKeyHex: hex,
                                  peerX25519PublicHex: xHex,
                                  trustIncomingSync: trustLan,
                                );
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                _p2p.invalidateInterestCache();
                                await _loadChats();
                                final list = await _store.loadChatEntries();
                                final convId = await ConversationId.fromEd25519PublicKeys(me, peer);
                                final entry = list.firstWhere((e) => e.conversationId == convId);
                                if (mounted) await _openChat(entry);
                              },
                              child: const Text('Создать чат'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
    nameCtl.dispose();
    keyCtl.dispose();
    x25519Ctl.dispose();
  }

  Future<void> _showNewGroup() async {
    final hasSub = await _prefs.hasActiveSubscription();
    if (!hasSub) {
      if (mounted) {
        AppSnack.show(
          context,
          'Создание и поддержка групповых чатов доступны только при активной подписке.',
        );
      }
      return;
    }
    final titleCtl = TextEditingController();
    final rows = <_MemberRow>[_MemberRow()];
    final formKey = GlobalKey<FormState>();
    var trustGroupLan = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.78,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
                  return Material(
                    color: const Color(0xFF1A1524),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Form(
                        key: formKey,
                        child: ListView(
                          controller: scrollController,
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Text(
                              'Новая группа',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Для защищённой группы укажите участникам Ed25519 и X25519. '
                              'X25519 нужен для безопасной рассылки группового ключа.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: titleCtl,
                              decoration: const InputDecoration(
                                labelText: 'Название группы',
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? 'Введите название' : null,
                            ),
                            const SizedBox(height: 16),
                            ...rows.asMap().entries.map((e) {
                              final i = e.key;
                              final row = e.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: row.name,
                                        decoration: InputDecoration(
                                          labelText: 'Участник ${i + 1}',
                                          hintText: 'Имя',
                                        ),
                                        validator: (v) {
                                          final keyOk =
                                              parseEd25519PublicKeyHex(row.key.text) != null;
                                          if (!keyOk && (v == null || v.isEmpty)) {
                                            return null;
                                          }
                                          if (!keyOk && (v != null && v.isNotEmpty)) {
                                            return 'Укажите ключ';
                                          }
                                          if (keyOk && (v == null || v.trim().isEmpty)) {
                                            return 'Имя';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: row.key,
                                        decoration: const InputDecoration(
                                          labelText: 'Ключ hex',
                                        ),
                                        validator: (v) {
                                          final nameEmpty = row.name.text.trim().isEmpty;
                                          final keyEmpty = (v == null || v.trim().isEmpty);
                                          if (nameEmpty && keyEmpty) return null;
                                          if (parseEd25519PublicKeyHex(v ?? '') == null) {
                                            return '64 hex';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: row.xKey,
                                        decoration: const InputDecoration(
                                          labelText: 'X25519 hex',
                                        ),
                                        validator: (v) {
                                          final nameEmpty = row.name.text.trim().isEmpty;
                                          final keyEmpty = row.key.text.trim().isEmpty;
                                          final xEmpty = (v == null || v.trim().isEmpty);
                                          if (nameEmpty && keyEmpty && xEmpty) return null;
                                          if (parseX25519PublicKeyHex(v ?? '') == null) {
                                            return '64 hex';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            TextButton.icon(
                              onPressed: () {
                                setModal(() => rows.add(_MemberRow()));
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить участника'),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Доверять групповой рассылке в LAN'),
                              subtitle: Text(
                                'Иначе чужие push по Wi‑Fi не применяются',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
                              ),
                              value: trustGroupLan,
                              onChanged: (v) => setModal(() => trustGroupLan = v),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () async {
                                if (!(formKey.currentState?.validate() ?? false)) return;
                                final members = <GroupMemberEntry>[];
                                final myPub = await widget.identity.ed25519PublicKey();
                                final myXPub = await widget.identity.x25519PublicKey();
                                final myHex = ed25519PublicKeyToHex(myPub);
                                final myXHex = x25519PublicKeyToHex(myXPub);
                                members.add(
                                  GroupMemberEntry(
                                    displayName: 'Вы',
                                    publicKeyHex: myHex,
                                    x25519PublicKeyHex: myXHex,
                                  ),
                                );
                                for (final row in rows) {
                                  final n = row.name.text.trim();
                                  final k = row.key.text.trim();
                                  final x = row.xKey.text.trim();
                                  if (n.isEmpty && k.isEmpty && x.isEmpty) continue;
                                  final pk = parseEd25519PublicKeyHex(k);
                                  final xPk = parseX25519PublicKeyHex(x);
                                  if (pk == null) continue;
                                  if (xPk == null) continue;
                                  if (ed25519PublicKeysEqual(pk, myPub)) continue;
                                  members.add(
                                    GroupMemberEntry(
                                      displayName: n,
                                      publicKeyHex: k.replaceAll(RegExp(r'\s'), '').toLowerCase(),
                                      x25519PublicKeyHex: x.replaceAll(RegExp(r'\s'), '').toLowerCase(),
                                    ),
                                  );
                                }
                                if (members.length < 2) {
                                  if (context.mounted) {
                                    AppSnack.show(
                                      context,
                                      'Добавьте хотя бы одного другого участника с ключом',
                                    );
                                  }
                                  return;
                                }
                                final st = await _store.openGroupConversation(
                                  title: titleCtl.text.trim(),
                                  members: members,
                                  trustIncomingSync: trustGroupLan,
                                );
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                _p2p.invalidateInterestCache();
                                await _loadChats();
                                final list = await _store.loadChatEntries();
                                final entry = list.firstWhere((e) => e.conversationId == st.conversationId);
                                if (mounted) await _openChat(entry);
                              },
                              child: const Text('Создать группу'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
    titleCtl.dispose();
    for (final r in rows) {
      r.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visibleChats = _chats.where((e) => !_p2p.isHiddenFromMainList(e)).toList();
    return MessengerBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.2),
          surfaceTintColor: Colors.transparent,
          title: Row(
            children: [
              const Text('Secure Chats'),
              const SizedBox(width: 10),
              FutureBuilder<bool>(
                future: _prefs.hasActiveSubscription(),
                builder: (context, s) => SecureBadge(
                  label: (s.data ?? false) ? 'PRO PRIORITY' : 'STANDARD',
                  icon: (s.data ?? false) ? Icons.bolt_rounded : Icons.shield_outlined,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Заблокировать',
              onPressed: widget.onLock,
              icon: const Icon(Icons.lock_outline_rounded),
            ),
          ],
        ),
        drawer: Drawer(
          backgroundColor: const Color(0xFF101528),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _pickMyAvatar,
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: cs.primary.withValues(alpha: 0.3),
                          backgroundImage: _myAvatarPath == null ? null : FileImage(File(_myAvatarPath!)),
                          child: _myAvatarPath == null ? const Icon(Icons.person_rounded) : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                      child: Text(
                          'SecureP2P',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Сменить аватар',
                        onPressed: _pickMyAvatar,
                        icon: const Icon(Icons.photo_camera_outlined),
                      ),
                      IconButton(
                        tooltip: 'Удалить аватар',
                        onPressed: _myAvatarPath == null ? null : _deleteMyAvatar,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.fingerprint_rounded),
                  title: const Text('Код сверки (~15 мин)'),
                  subtitle: Text(
                    'По публичным ключам; совпадает у того, кто уже знает ваши ключи (например после QR).\n$_peerIdDisplay',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Настройки'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (ctx) => AppSettingsPage(prefs: _prefs),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Профиль приватности'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickPrivacyProfile();
                  },
                ),
                FutureBuilder<String>(
                  future: _prefs.privacyProfile(),
                  builder: (context, profileSnap) {
                    if (profileSnap.data != AppPreferences.privacyParanoid) {
                      return const SizedBox.shrink();
                    }
                    return FutureBuilder<bool>(
                      future: _prefs.sendAvatarInSync(),
                      builder: (context, sendSnap) {
                        return SwitchListTile(
                          secondary: const Icon(Icons.account_circle_outlined),
                          title: const Text('Отправлять аватар в sync'),
                          subtitle: const Text('Paranoid: можно скрыть аватар от собеседников'),
                          value: sendSnap.data ?? false,
                          onChanged: (_) => _toggleAvatarSync(),
                        );
                      },
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Заблокировать'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onLock();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Скрытые чаты'),
                  onTap: () {
                    Navigator.pop(context);
                    final hidden = _chats.where(_p2p.isHiddenFromMainList).toList();
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (ctx) => HiddenChatsPage(
                          identity: widget.identity,
                          store: _store,
                          p2p: _p2p,
                          internet: _internetHub,
                          hiddenEntries: hidden,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Отладка LAN'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (ctx) => const DebugConsolePage()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.security_rounded),
                  title: const Text('Состояние защиты'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (ctx) => SecurityStatusPage(
                          prefs: _prefs,
                          chatCount: _chats.length,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history_edu_outlined),
                  title: const Text('Журнал безопасности'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (ctx) => const SecurityJournalPage()),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.warning_amber_rounded, color: cs.error),
                  title: Text('Panic Lock', style: TextStyle(color: cs.error)),
                  subtitle: const Text('Мгновенный wipe и закрытие приложения'),
                  onTap: () async {
                    Navigator.pop(context);
                    await SecurityAuditLog.instance.append('panic_lock_from_drawer');
                    await widget.onPanicLock();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_forever, color: cs.error),
                  title: Text('Удалить все данные', style: TextStyle(color: cs.error)),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmWipe();
                  },
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showNewMenu,
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('Новый чат'),
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            color: Theme.of(context).colorScheme.primary,
            onRefresh: _loadChats,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 88, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SecureCard(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => setState(() => _keysExpanded = !_keysExpanded),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      children: [
                                        Icon(Icons.key_rounded, color: cs.primary, size: 22),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Ключи',
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const Spacer(),
                                        Icon(
                                          _keysExpanded
                                              ? Icons.keyboard_arrow_up_rounded
                                              : Icons.keyboard_arrow_down_rounded,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_keysExpanded) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Показ по отдельности · нажмите глаз или копирование',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white30),
                                  ),
                                  const SizedBox(height: 14),
                                  _keyRow(
                                    context: context,
                                    subtitle: 'Ed25519 — кто я',
                                    value: _myPublicHex,
                                    visible: _showEd25519,
                                    onToggle: _toggleEd25519,
                                    onCopy: _copyEd25519,
                                  ),
                                  const SizedBox(height: 14),
                                  _keyRow(
                                    context: context,
                                    subtitle: 'X25519 — сквозное шифрование текста',
                                    value: _myX25519Hex,
                                    visible: _showX25519,
                                    onToggle: _toggleX25519,
                                    onCopy: _copyX25519,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Один Wi‑Fi, без серверов. Долгое молчание в LAN скрывает личный чат.',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white30),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.04, curve: Curves.easeOut),
                    ],
                  ),
                ),
              ),
              if (visibleChats.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.forum_outlined, size: 72, color: cs.primary.withValues(alpha: 0.45))
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .scale(
                                duration: 2.seconds,
                                begin: const Offset(1, 1),
                                end: const Offset(1.06, 1.06),
                                curve: Curves.easeInOut,
                              ),
                          const SizedBox(height: 20),
                          Text(
                            _chats.isEmpty ? 'Пока нет чатов' : 'Нет видимых чатов',
                            style: Theme.of(context).textTheme.titleMedium,
                          ).animate().fadeIn(delay: 100.ms),
                          const SizedBox(height: 8),
                          Text(
                            _chats.isEmpty
                                ? 'Создайте личный диалог или группу.\nЛичные чаты в одной Wi‑Fi синхронизируются по UDP (multicast).'
                                : 'Личные диалоги скрыты: нет heartbeat от собеседника в LAN или истекло время ожидания.\nОткройте приложение у контакта в той же сети.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
                          ).animate().fadeIn(delay: 180.ms),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final e = visibleChats[index];
                        final icon = e.type == ChatType.group ? Icons.groups_rounded : Icons.person_rounded;
                        final peerFp = e.type == ChatType.direct
                            ? () {
                                final pk = parseEd25519PublicKeyHex(e.peerPublicKeyHex ?? '');
                                return pk == null ? null : ConversationId.fingerprint(pk);
                              }()
                            : null;
                        final online = (peerFp != null && _p2p.isPeerOnline(peerFp)) ||
                            _internetHub.isLinked(e.conversationId);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              onTap: () => _openChat(e),
                              borderRadius: BorderRadius.circular(18),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                child: Row(
                                  children: [
                                    if (_chatColors[e.conversationId] != null)
                                      Container(
                                        width: 4,
                                        height: 38,
                                        margin: const EdgeInsets.only(right: 10),
                                        decoration: BoxDecoration(
                                          color: Color(_chatColors[e.conversationId]!),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                    CircleAvatar(
                                      backgroundColor: cs.primary.withValues(alpha: 0.35),
                                      backgroundImage: _peerAvatarPathByConversation[e.conversationId] == null
                                          ? null
                                          : FileImage(File(_peerAvatarPathByConversation[e.conversationId]!)),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          if (_peerAvatarPathByConversation[e.conversationId] == null)
                                            Center(child: Icon(icon, color: Colors.white)),
                                          if (online)
                                            Positioned(
                                              right: -1,
                                              bottom: -1,
                                              child: Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: Colors.lightGreenAccent,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: const Color(0xFF1A1524), width: 2),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e.title,
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            e.lastPreview ?? (e.type == ChatType.group ? 'Группа' : 'Личный чат'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Colors.white54,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                            .animate(delay: (40 * index).ms)
                            .fadeIn(duration: 280.ms)
                            .slideX(begin: 0.03, curve: Curves.easeOutCubic);
                      },
                      childCount: visibleChats.length,
                    ),
                  ),
                ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyRow({
    required BuildContext context,
    required String subtitle,
    required String value,
    required bool visible,
    required Future<void> Function() onToggle,
    required Future<void> Function() onCopy,
  }) {
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          fontSize: 11,
          color: Colors.white70,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white38),
              ),
            ),
            IconButton(
              tooltip: visible ? 'Скрыть' : 'Показать',
              icon: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => onToggle(),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Material(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => onCopy(),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: visible
                        ? Text(value, maxLines: 4, style: mono)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(minHeight: 42),
                              alignment: Alignment.center,
                              color: const Color(0xFF0A0A0A),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              child: const Text(
                                'Скрыто',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 6, top: 2),
                    child: Icon(Icons.copy_rounded, size: 18, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MemberRow {
  final name = TextEditingController();
  final key = TextEditingController();
  final xKey = TextEditingController();

  void dispose() {
    name.dispose();
    key.dispose();
    xKey.dispose();
  }
}
