import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class InviteScannerPage extends StatefulWidget {
  const InviteScannerPage({super.key});

  @override
  State<InviteScannerPage> createState() => _InviteScannerPageState();
}

class _InviteScannerPageState extends State<InviteScannerPage> {
  final _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Сканировать приглашение'),
        backgroundColor: Colors.black87,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.trim().isNotEmpty) {
                  Navigator.of(context).pop<String>(v);
                  return;
                }
              }
            },
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Наведите камеру на QR из Dart AUT. Данные не уходят на сервер.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
