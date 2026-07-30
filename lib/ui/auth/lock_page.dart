import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../auth/secure_app_repository.dart';
import '../../identity/user_identity.dart';
import '../../security/security_audit_log.dart';
import '../widgets/messenger_backdrop.dart';
import '../widgets/secure_ui.dart';

class LockPage extends StatefulWidget {
  const LockPage({
    super.key,
    required this.repository,
    required this.onUnlocked,
    required this.onPanicRequested,
  });

  final SecureAppRepository repository;
  final void Function(UserIdentity identity) onUnlocked;
  final Future<void> Function() onPanicRequested;

  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  final _pwd = TextEditingController();
  bool _busy = false;
  bool _showPwd = false;
  int _shake = 0;
  AppPasswordKind _kind = AppPasswordKind.text;

  @override
  void initState() {
    super.initState();
    _loadKind();
  }

  @override
  void dispose() {
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _loadKind() async {
    final k = await widget.repository.storedPasswordKind;
    if (mounted) setState(() => _kind = k);
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    try {
      final id = await widget.repository.tryUnlock(_pwd.text);
      if (!mounted) return;
      if (id == null) {
        await SecurityAuditLog.instance.append(
          'unlock_failed',
          details: {'attempts': widget.repository.failedUnlockAttempts},
        );
        if (widget.repository.shouldPanicWipe) {
          await SecurityAuditLog.instance.append(
            'panic_wipe_triggered_by_failed_unlock_limit',
            details: {'limit': SecureAppRepository.maxUnlockAttemptsPerSession},
          );
          await widget.onPanicRequested();
          return;
        }
        setState(() {
          _shake++;
          _pwd.clear();
        });
        return;
      }
      await SecurityAuditLog.instance.append('unlock_success');
      widget.onUnlocked(id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: MessengerBackdrop(
        child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SecureCard(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                    child: Column(
                      children: [
                        const SecureBadge(label: 'Protected session', icon: Icons.shield_outlined),
                        const SizedBox(height: 14),
                      Icon(Icons.lock_rounded, size: 64, color: cs.primary)
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .scale(
                            duration: 1800.ms,
                            begin: const Offset(1, 1),
                            end: const Offset(1.04, 1.04),
                            curve: Curves.easeInOut,
                          ),
                      const SizedBox(height: 20),
                      const SecureSectionTitle(
                        'Вход в защищённый профиль',
                        subtitle: 'Доступ к ключам и переписке только после локальной проверки',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _kind == AppPasswordKind.pin
                            ? 'Введите ПИН для доступа к ключам на этом устройстве.'
                            : 'Введите пароль для доступа к ключам на этом устройстве.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        key: ValueKey(_shake),
                        controller: _pwd,
                        obscureText: !_showPwd,
                        keyboardType:
                            _kind == AppPasswordKind.pin ? TextInputType.number : TextInputType.visiblePassword,
                        inputFormatters:
                            _kind == AppPasswordKind.pin ? [FilteringTextInputFormatter.digitsOnly] : null,
                        onSubmitted: (_) => _unlock(),
                        decoration: InputDecoration(
                          labelText: _kind == AppPasswordKind.pin ? 'ПИН' : 'Пароль',
                          suffixIcon: IconButton(
                            tooltip: _showPwd ? 'Скрыть' : 'Показать',
                            onPressed: () => setState(() => _showPwd = !_showPwd),
                            icon: Icon(_showPwd ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                          ),
                        ),
                      )
                          .animate(target: _shake.toDouble())
                          .shake(hz: 4.0, curve: Curves.easeInOut, duration: 400.ms),
                      const SizedBox(height: 20),
                      Text(
                        'Осталось попыток: ${widget.repository.unlockAttemptsLeft}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _busy ? null : _unlock,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(220, 62),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        child: _busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.vpn_key_rounded, size: 30),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ),
      ),
    );
  }
}
