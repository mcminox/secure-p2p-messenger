import 'dart:async';

import 'package:flutter/services.dart';

class WebrtcDeepLinkBridge {
  WebrtcDeepLinkBridge._();
  static final WebrtcDeepLinkBridge instance = WebrtcDeepLinkBridge._();

  static const MethodChannel _channel = MethodChannel('spm/deeplink');
  final StreamController<String> _stream = StreamController<String>.broadcast();
  bool _initialized = false;
  String? _lastPending;

  Stream<String> get stream => _stream.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final raw = call.arguments;
        if (raw is String && raw.isNotEmpty) {
          _lastPending = raw;
          _stream.add(raw);
        }
      }
    });
    try {
      final initial = await _channel.invokeMethod<String>('getInitialLink');
      if (initial != null && initial.isNotEmpty) {
        _lastPending = initial;
        _stream.add(initial);
      }
    } catch (_) {}
  }

  String? takePending() {
    final v = _lastPending;
    _lastPending = null;
    return v;
  }

  void injectLocal(String raw) {
    if (raw.isEmpty) return;
    _lastPending = raw;
    _stream.add(raw);
  }
}
