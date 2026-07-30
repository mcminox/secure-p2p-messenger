import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/messenger_backdrop.dart';
import '../widgets/secure_ui.dart';

class PanicModePage extends StatelessWidget {
  const PanicModePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MessengerBackdrop(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SecureCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.redAccent),
                      const SizedBox(height: 16),
                      const SecureSectionTitle(
                        'Panic mode активирован',
                        subtitle: 'Ключи и локальные данные удалены из приложения',
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Приложение переведено в аварийный режим.\n\n'
                        'Для продолжения удалите приложение и установите заново.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => SystemNavigator.pop(),
                        child: const Text('Закрыть'),
                      ),
                    ],
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
