import 'package:flutter/foundation.dart';

import '../prefs/app_preferences.dart';
import 'app_integrity_service.dart';
import 'server_api_client.dart';

class LicenseGuard {
  LicenseGuard({
    ServerApiClient? api,
    AppPreferences? prefs,
    AppIntegrityService? integrity,
  })  : _api = api ?? ServerApiClient(),
        _prefs = prefs ?? AppPreferences(),
        _integrity = integrity ?? AppIntegrityService();

  final ServerApiClient _api;
  final AppPreferences _prefs;
  final AppIntegrityService _integrity;

  Future<bool> canAccessSecureFlows() async {
    final enforce = await _prefs.licenseEnforcementEnabled();
    if (!enforce) return true;

    final accessToken = await _prefs.accessToken();
    final userId = await _prefs.userId();
    final deviceId = await _prefs.deviceId();
    final devicePub = await _prefs.devicePubkey();
    final appBuild = await _prefs.appBuildFingerprint();
    if (accessToken == null || userId == null || deviceId == null || devicePub == null) {
      return false;
    }

    final sig = await _integrity.readSignals();
    if (sig.isHighRisk) {
      await _reportRisk(userId, deviceId, 'hook_framework_detected', sig.toJson(), accessToken);
      return false;
    }

    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      final issue = await _api.postJson(
        '/v1/license/issue',
        {
          'user_id': userId,
          'device_id': deviceId,
          'device_pubkey': devicePub,
          'app_build_fingerprint': appBuild ?? 'unknown',
          'nonce': nonce,
        },
        accessToken: accessToken,
      );

      final token = issue['license_token']?.toString();
      if (token == null || token.isEmpty) {
        return false;
      }
      final verify = await _api.postJson(
        '/v1/license/verify',
        {
          'license_token': token,
          'nonce': nonce,
          'proof': 'device-local-proof',
        },
        accessToken: accessToken,
      );
      final valid = verify['valid'] == true;
      if (!valid) {
        await _reportRisk(userId, deviceId, 'license_rejected', {'verify': verify}, accessToken);
      }
      return valid;
    } catch (e) {
      debugPrint('license check failed: $e');
      return false;
    }
  }

  Future<void> _reportRisk(
    String userId,
    String deviceId,
    String event,
    Map<String, dynamic> payload,
    String accessToken,
  ) async {
    try {
      await _api.postJson(
        '/v1/risk/report',
        {
          'user_id': userId,
          'device_id': deviceId,
          'event': event,
          'payload': payload,
        },
        accessToken: accessToken,
      );
    } catch (_) {}
  }
}
