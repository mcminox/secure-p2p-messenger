import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../p2p/internet_p2p_hub.dart';
import '../security/license_guard.dart';
import '../util/scanner_support.dart';
import '../util/webrtc_deeplink_bridge.dart';
import 'invite_scanner_page.dart';
import 'widgets/app_snack.dart';
import 'widgets/secure_ui.dart';

class InternetConnectSheet extends StatefulWidget {
  const InternetConnectSheet({
    super.key,
    required this.conversationId,
    required this.hub,
    this.autoStartOffer = false,
  });

  final String conversationId;
  final InternetP2pHub hub;
  final bool autoStartOffer;

  @override
  State<InternetConnectSheet> createState() => _InternetConnectSheetState();
}

class _InternetConnectSheetState extends State<InternetConnectSheet> {
  final _pasteCtl = TextEditingController();
  final _connectTokenCtl = TextEditingController();
  bool _busy = false;
  final _licenseGuard = LicenseGuard();
  StreamSubscription<String>? _deepLinkSub;
  bool _didAutoStartOffer = false;

  String? _pendingOfferJson;

  String? _generatedAnswerJson;
  String? _serverSessionId;
  String? _serverSessionSecret;

  @override
  void initState() {
    super.initState();
    _deepLinkSub = WebrtcDeepLinkBridge.instance.stream.listen(_handleIncomingDeepLink);
    final pending = WebrtcDeepLinkBridge.instance.takePending();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleIncomingDeepLink(pending);
      });
    }
    if (widget.autoStartOffer) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _didAutoStartOffer) return;
        _didAutoStartOffer = true;
        await _createOffer();
      });
    }
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _pasteCtl.dispose();
    _connectTokenCtl.dispose();
    super.dispose();
  }

  String _toShareLink(String rawJson) {
    final payload = base64UrlEncode(utf8.encode(rawJson));
    return 'dartaut://webrtc?payload=$payload';
  }

  String? _fromShareLink(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final uri = Uri.tryParse(s);
    if (uri == null || uri.scheme != 'dartaut' || uri.host != 'webrtc') {
      return s;
    }
    final payload = uri.queryParameters['payload'];
    if (payload == null || payload.isEmpty) return null;
    try {
      final bytes = base64Url.decode(base64Url.normalize(payload));
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleIncomingDeepLink(String rawLink) async {
    if (!mounted) return;
    final decoded = _fromShareLink(rawLink);
    if (decoded == null) return;
    final parsed = _tryRole(decoded);
    if (parsed == null) return;
    _pasteCtl.text = decoded;
    if (parsed.$2 == 'offer') {
      await _acceptOfferPaste();
      return;
    }
    if (parsed.$2 == 'answer' && _pendingOfferJson != null) {
      await _applyAnswer();
    }
  }

  (String, String)? _tryRole(String rawJson) {
    try {
      final j = jsonDecode(rawJson) as Map<String, dynamic>;
      final role = j['role'] as String?;
      final cid = j['cid'] as String?;
      if (role == null || cid == null) return null;
      if (cid != widget.conversationId) return null;
      return (cid, role);
    } catch (_) {
      return null;
    }
  }

  Future<void> _createOffer() async {
    final allow = await _licenseGuard.canAccessSecureFlows();
    if (!allow) {
      if (mounted) AppSnack.show(context, 'Лицензия не подтверждена. Интернет-коннект заблокирован.');
      return;
    }
    setState(() => _busy = true);
    try {
      final j = await widget.hub.createOfferForConversation(widget.conversationId);
      final link = _toShareLink(j);
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        setState(() {
          _pendingOfferJson = j;
          _generatedAnswerJson = null;
          _pasteCtl.clear();
        });
        AppSnack.show(context, 'Offer скопирован. Откроется шаринг.');
      }
      await Share.share(
        link,
        subject: 'Dart AUT WebRTC offer',
      );
    } catch (e) {
      if (mounted) AppSnack.show(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createServerOffer() async {
    final allow = await _licenseGuard.canAccessSecureFlows();
    if (!allow) {
      if (mounted) AppSnack.show(context, 'Лицензия не подтверждена. Интернет-коннект заблокирован.');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await widget.hub.publishServerRendezvous(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _serverSessionId = res.sessionId;
        _serverSessionSecret = res.secret;
      });
      AppSnack.show(context, 'Ожидание ответа через сервер открыто');
      await widget.hub.pollServerAnswerAndApply(
        conversationId: widget.conversationId,
        sessionId: res.sessionId,
        secret: res.secret,
      );
      if (mounted) {
        AppSnack.show(context, 'Серверный RTC-канал подключён');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) AppSnack.show(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectViaToken() async {
    final allow = await _licenseGuard.canAccessSecureFlows();
    if (!allow) {
      if (mounted) AppSnack.show(context, 'Лицензия не подтверждена. Интернет-коннект заблокирован.');
      return;
    }
    final token = _connectTokenCtl.text.trim();
    if (token.isEmpty) {
      if (mounted) AppSnack.show(context, 'Введите connect-token собеседника');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.hub.connectViaServerToken(
        conversationId: widget.conversationId,
        targetConnectToken: token,
      );
      if (mounted) {
        AppSnack.show(context, 'Подключено через серверный поиск по токену');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) AppSnack.show(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyAnswer() async {
    final raw = _fromShareLink(_pasteCtl.text) ?? '';
    if (raw.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.hub.applyAnswerJson(raw);
      if (mounted) {
        AppSnack.show(context, 'Интернет-канал открыт');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) AppSnack.show(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptOfferPaste() async {
    final raw = _fromShareLink(_pasteCtl.text) ?? '';
    if (raw.isEmpty) return;
    setState(() => _busy = true);
    try {
      final ans = await widget.hub.acceptOfferJson(raw);
      final link = _toShareLink(ans);
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        setState(() {
          _generatedAnswerJson = ans;
          _pendingOfferJson = null;
          _pasteCtl.clear();
        });
        AppSnack.show(context, 'Answer скопирован. Откроется шаринг.');
      }
      await Share.share(
        link,
        subject: 'Dart AUT WebRTC answer',
      );
    } catch (e) {
      if (mounted) AppSnack.show(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanIntoPaste() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const InviteScannerPage()),
    );
    if (raw != null && mounted) {
      _pasteCtl.text = raw;
      setState(() {});
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final t = data?.text?.trim() ?? '';
    if (t.isEmpty) {
      if (mounted) AppSnack.show(context, 'Буфер обмена пуст');
      return;
    }
    _pasteCtl.text = t;
    if (mounted) setState(() {});
  }

  Widget _qrBlock(String data) {
    return Center(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: QrImageView(
            data: data,
            size: 200,
            version: QrVersions.auto,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final linked = widget.hub.isLinked(widget.conversationId);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1228),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFB388FF).withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SecureSectionTitle(
                'Быстрый серверный connect',
                subtitle: 'Поиск пользователя по connect-token без прямого обмена IP/SDP',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _connectTokenCtl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Connect token собеседника',
                  hintText: 'Например: A1B2C3D4E5F6',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _connectViaToken,
                    icon: const Icon(Icons.travel_explore_rounded),
                    label: const Text('Найти и подключиться'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _createServerOffer,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Открыть себя в поиске'),
                  ),
                ],
              ),
              if (_serverSessionId != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Сессия поиска активна: $_serverSessionId',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Text(
                'Интернет без сервера',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Простой режим: создайте offer -> второй человек вставляет -> answer уходит обратно автоматически.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.35),
              ),
              const SizedBox(height: 16),
              if (linked) ...[
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () async {
                          await widget.hub.disconnect();
                          if (mounted) setState(() {});
                        },
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Разорвать интернет-канал'),
                ),
              ] else if (_generatedAnswerJson != null) ...[
                Text(
                  'Answer отправлен инициатору',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'На вашем устройстве канал уже готов. Нужен последний шаг у инициатора: вставить answer и нажать «Подключиться».',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _generatedAnswerJson!));
                          if (!context.mounted) return;
                          AppSnack.show(context, 'Скопировано');
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Копировать'),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () async {
                        await Share.share(
                          _toShareLink(_generatedAnswerJson!),
                          subject: 'Dart AUT WebRTC answer',
                        );
                      },
                      icon: const Icon(Icons.share_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _qrBlock(_generatedAnswerJson!),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Ожидать подключения'),
                ),
              ] else if (_pendingOfferJson != null) ...[
                Text('Отправьте собеседнику offer', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  'Offer уже скопирован и отправлен через системный шаринг.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                _qrBlock(_pendingOfferJson!),
                const SizedBox(height: 16),
                TextField(
                  controller: _pasteCtl,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Вставьте answer',
                    hintText: 'Ссылка dartaut://webrtc... или JSON answer',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : _pasteFromClipboard,
                      icon: const Icon(Icons.content_paste_rounded),
                      label: const Text('Вставить'),
                    ),
                    if (inviteScannerSupported)
                      TextButton.icon(
                        onPressed: _busy ? null : _scanIntoPaste,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('Скан'),
                      ),
                    FilledButton(
                      onPressed: _busy ? null : _applyAnswer,
                      child: const Text('Подключиться'),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _pendingOfferJson = null;
                            _pasteCtl.clear();
                          }),
                  child: const Text('Начать заново'),
                ),
              ] else ...[
                Text('Инициатор', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _createOffer,
                  icon: const Icon(Icons.vpn_key_rounded),
                  label: const Text('Создать приглашение (offer)'),
                ),
                const SizedBox(height: 24),
                Text('Собеседник', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _pasteCtl,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Вставьте offer инициатора',
                    hintText: 'Ссылка dartaut://webrtc... или JSON offer',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : _pasteFromClipboard,
                      icon: const Icon(Icons.content_paste_rounded),
                      label: const Text('Вставить'),
                    ),
                    if (inviteScannerSupported)
                      TextButton.icon(
                        onPressed: _busy ? null : _scanIntoPaste,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('Скан'),
                      ),
                    FilledButton.tonal(
                      onPressed: _busy ? null : _acceptOfferPaste,
                      child: const Text('Подключиться'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
