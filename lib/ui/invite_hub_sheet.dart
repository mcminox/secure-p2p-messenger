import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../identity/rotating_peer_id.dart';
import '../invite/invite_codec.dart';

class InviteHubSheet extends StatefulWidget {
  const InviteHubSheet({
    super.key,
    required this.ed25519Hex,
    required this.x25519Hex,
    required this.rotating,
    required this.connectToken,
  });

  final String ed25519Hex;
  final String x25519Hex;
  final RotatingPeerId rotating;
  final String connectToken;

  @override
  State<InviteHubSheet> createState() => _InviteHubSheetState();
}

class _InviteHubSheetState extends State<InviteHubSheet> {
  final _nameCtl = TextEditingController();
  String _shortCode = '…';
  String? _nameError;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _refreshCode();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => _refreshCode());
  }

  @override
  void dispose() {
    _t?.cancel();
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _refreshCode() async {
    final v = await widget.rotating.current();
    if (mounted) setState(() => _shortCode = v);
  }

  String _payload() {
    final n = _nameCtl.text.trim();
    return InviteCodec.buildQuickToken(
      displayName: n.isEmpty ? 'Контакт' : n,
      ed25519Hex: widget.ed25519Hex,
      x25519Hex: widget.x25519Hex,
    );
  }

  String _quickPayload() {
    final n = _nameCtl.text.trim();
    return InviteCodec.buildQuickToken(
      displayName: n,
      ed25519Hex: widget.ed25519Hex,
      x25519Hex: widget.x25519Hex,
    );
  }

  Future<void> _copyQuickPayload() async {
    if (!_validateName()) return;
    final quick = _quickPayload();
    await Clipboard.setData(ClipboardData(text: quick));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Быстрый код приглашения скопирован')),
      );
    }
  }

  Future<void> _copyJsonPayload() async {
    if (!_validateName()) return;
    final json = InviteCodec.buildCompactJson(
      displayName: _nameCtl.text.trim(),
      ed25519Hex: widget.ed25519Hex,
      x25519Hex: widget.x25519Hex,
    );
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('JSON приглашения скопирован')),
      );
    }
  }

  bool _validateName() {
    final n = _nameCtl.text.trim();
    if (n.isEmpty) {
      setState(() => _nameError = 'Введите имя перед отправкой приглашения');
      return false;
    }
    setState(() => _nameError = null);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final quick = _payload();
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Строковое приглашение',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Скопируйте одну строку и отправьте собеседнику. На его стороне это сразу создаст контакт и откроет шаг подключения.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.35),
              ),
              const SizedBox(height: 16),
              Text('Код сверки сейчас', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              SelectableText(
                _shortCode,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 1.2,
                      color: cs.secondary,
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ваш connect-token (поиск без IP)',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      widget.connectToken.isEmpty ? 'не задан' : widget.connectToken,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            color: cs.secondary,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtl,
                decoration: InputDecoration(
                  labelText: 'Как вас подписать у контакта',
                  hintText: 'Например, Анна',
                  errorText: _nameError,
                ),
                onChanged: (_) => setState(() {
                  _nameError = null;
                }),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: SelectableText(
                  quick,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: cs.secondary,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  if (!_validateName()) return;
                  final quick = _quickPayload();
                  await Share.share(quick);
                },
                icon: const Icon(Icons.share_rounded),
                label: const Text('Поделиться'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyQuickPayload,
                      icon: const Icon(Icons.bolt_rounded),
                      label: const Text('Копировать быстрый код'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyJsonPayload,
                      icon: const Icon(Icons.copy_all_rounded),
                      label: const Text('Копировать JSON'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'На другом устройстве: «Вставить приглашение» -> вставить строку.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
