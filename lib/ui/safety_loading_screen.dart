import 'dart:async';

import 'package:flutter/material.dart';

class SafetyLoadingScreen extends StatefulWidget {
  const SafetyLoadingScreen({super.key, this.message});

  final String? message;

  @override
  State<SafetyLoadingScreen> createState() => _SafetyLoadingScreenState();
}

class _SafetyLoadingScreenState extends State<SafetyLoadingScreen> {
  static const _tips = [
    'Не вводите пароли на подозрительных сайтах и не повторяйте один пароль везде.',
    'Проверяйте адрес сайта в строке браузера: мошенники подделывают похожие домены.',
    'Сообщения в этом приложении идут по локальной сети — посторонний Wi‑Fi ненадёжен.',
    'Включайте «Доверять синхронизации» только для людей, которых вы знаете лично.',
    'Сравните код безопасности с собеседником голосом или при встрече.',
    'Не открывайте вложения от незнакомых отправителей.',
    'Обновляйте систему и приложения — так закрываются известные уязвимости.',
    'Делайте резервные копии важных данных отдельно от основного устройства.',
  ];

  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _i = DateTime.now().millisecond % _tips.length;
    _t = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % _tips.length);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF120A1A),
              cs.primary.withValues(alpha: 0.25),
              const Color(0xFF0D0814),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const SizedBox(height: 24),
                SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  widget.message ?? 'Загрузка…',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Icon(Icons.shield_outlined, size: 36, color: cs.secondary.withValues(alpha: 0.9)),
                const SizedBox(height: 12),
                Text(
                  'Безопасность',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white54,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      child: Text(
                        _tips[_i],
                        key: ValueKey<int>(_i),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                      ),
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
}
