import 'package:flutter/services.dart';

class AppIntegritySignals {
  AppIntegritySignals({
    required this.debuggerAttached,
    required this.rootDetected,
    required this.emulatorDetected,
    required this.hookDetected,
  });

  final bool debuggerAttached;
  final bool rootDetected;
  final bool emulatorDetected;
  final bool hookDetected;

  bool get isHighRisk => debuggerAttached || hookDetected;
  bool get isMediumRisk => rootDetected || emulatorDetected;

  Map<String, dynamic> toJson() => {
        'debugger_attached': debuggerAttached,
        'root_detected': rootDetected,
        'emulator_detected': emulatorDetected,
        'hook_detected': hookDetected,
      };
}

class AppIntegrityService {
  static const MethodChannel _ch = MethodChannel('spm/security');

  Future<AppIntegritySignals> readSignals() async {
    try {
      final data = await _ch.invokeMapMethod<String, dynamic>('getSecuritySignals');
      return AppIntegritySignals(
        debuggerAttached: data?['debuggerAttached'] == true,
        rootDetected: data?['rootDetected'] == true,
        emulatorDetected: data?['emulatorDetected'] == true,
        hookDetected: data?['hookDetected'] == true,
      );
    } catch (_) {
      return AppIntegritySignals(
        debuggerAttached: false,
        rootDetected: false,
        emulatorDetected: false,
        hookDetected: false,
      );
    }
  }
}
