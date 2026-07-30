import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../auth/secure_app_repository.dart';
import '../../identity/user_identity.dart';
import '../widgets/app_snack.dart';
import '../widgets/messenger_backdrop.dart';
import '../widgets/secure_ui.dart';
import 'password_kind_selector.dart';

class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({
    super.key,
    required this.repository,
    required this.onCompleted,
  });

  final SecureAppRepository repository;
  final void Function(UserIdentity identity) onCompleted;

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  AppPasswordKind _kind = AppPasswordKind.text;
  int _step = 0;
  bool _busy = false;
  bool _showP1 = false;
  bool _showP2 = false;
  String? _error;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await widget.repository.setupPasswordOnce(_p1.text, _kind);
      final id = await widget.repository.tryUnlock(_p1.text);
      if (id == null) {
        throw StateError('Не удалось завершить инициализацию ключей.');
      }
      if (!mounted) return;
      widget.onCompleted(id);
    } catch (e) {
      setState(() => _error = e.toString());
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
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: SecureCard(
                    child: _step == 0 ? _buildChooser() : _buildForm(cs),
                  ),
                ),
              ),
            ),
        ),
      ),
    );
  }

  Widget _buildChooser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Secure setup',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
        ).animate().fade().slideY(begin: 0.08, duration: 400.ms),
        const SizedBox(height: 8),
        const SecureBadge(label: 'Master key required', icon: Icons.key_rounded),
        const SizedBox(height: 12),
        Text(
          'Выберите тип мастер-секрета',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white70,
              ),
        ),
        const SizedBox(height: 24),
        PasswordKindSelector(
          selected: _kind,
          onChanged: (k) => setState(() => _kind = k),
        ),
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.center,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => setState(() {
              _step = 1;
              _error = null;
            }),
            icon: const Icon(Icons.vpn_key_rounded),
            label: const Text('Задать секрет'),
          ),
        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.06, delay: 200.ms),
      ],
    );
  }

  Widget _buildForm(ColorScheme cs) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.lock_rounded, size: 52, color: cs.primary)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .shimmer(duration: 2200.ms, color: cs.secondary.withValues(alpha: 0.45)),
          const SizedBox(height: 12),
          Text(
            _kind == AppPasswordKind.pin ? 'Задайте ПИН' : 'Задайте пароль',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _kind == AppPasswordKind.pin
                ? 'Только цифры, не короче 6. Этот ПИН нельзя восстановить без удаления данных.'
                : 'Не короче 10 символов. Пароль не хранится — только производные ключи в защищённом хранилище ОС.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _p1,
            obscureText: !_showP1,
            keyboardType: _kind == AppPasswordKind.pin ? TextInputType.number : TextInputType.visiblePassword,
            inputFormatters: _kind == AppPasswordKind.pin ? [FilteringTextInputFormatter.digitsOnly] : null,
            decoration: InputDecoration(
              labelText: _kind == AppPasswordKind.pin ? 'ПИН' : 'Пароль',
              suffixIcon: IconButton(
                tooltip: _showP1 ? 'Скрыть' : 'Показать',
                onPressed: () => setState(() => _showP1 = !_showP1),
                icon: Icon(_showP1 ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Введите значение';
              if (_kind == AppPasswordKind.pin) {
                if (!RegExp(r'^\d+$').hasMatch(v)) return 'Только цифры';
                if (v.length < 6) return 'Минимум 6 цифр';
              } else {
                if (v.length < 10) return 'Минимум 10 символов';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _p2,
            obscureText: !_showP2,
            keyboardType: _kind == AppPasswordKind.pin ? TextInputType.number : TextInputType.visiblePassword,
            inputFormatters: _kind == AppPasswordKind.pin ? [FilteringTextInputFormatter.digitsOnly] : null,
            decoration: InputDecoration(
              labelText: _kind == AppPasswordKind.pin ? 'Повтор ПИН' : 'Повтор пароля',
              suffixIcon: IconButton(
                tooltip: _showP2 ? 'Скрыть' : 'Показать',
                onPressed: () => setState(() => _showP2 = !_showP2),
                icon: Icon(_showP2 ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              ),
            ),
            validator: (v) => v != _p1.text ? 'Не совпадает' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    if (_formKey.currentState?.validate() ?? false) {
                      _submit();
                    } else {
                      AppSnack.show(context, 'Проверьте поля: формат не подходит.');
                    }
                  },
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить и продолжить'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _step = 0;
              _error = null;
            }),
            child: const Text('Назад к выбору типа'),
          ),
        ],
      ),
    );
  }
}
