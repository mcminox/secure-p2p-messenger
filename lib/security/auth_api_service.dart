import 'server_api_client.dart';

class AuthApiService {
  AuthApiService({ServerApiClient? api}) : _api = api ?? ServerApiClient();

  final ServerApiClient _api;

  Future<Map<String, dynamic>> login({
    required String email,
    required String passwordHash,
    required String deviceId,
  }) {
    return _api.postJson('/v1/auth/login', {
      'email': email,
      'password_hash': passwordHash,
      'device_id': deviceId,
    });
  }

  Future<Map<String, dynamic>> verifyMfa({
    required String userId,
    required String code,
  }) {
    return _api.postJson('/v1/auth/mfa/verify', {
      'user_id': userId,
      'code': code,
    });
  }

  Future<Map<String, dynamic>> createWebQrChallenge() {
    return _api.postJson('/v1/web/qr/challenge', {});
  }

  Future<Map<String, dynamic>> approveWebQrChallenge({
    required String challengeId,
    required String userId,
    required String deviceSignature,
    required String accessToken,
  }) {
    return _api.postJson(
      '/v1/web/qr/approve',
      {
        'challenge_id': challengeId,
        'user_id': userId,
        'device_signature': deviceSignature,
      },
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> profile({
    required String userId,
    required String accessToken,
  }) {
    return _api.postJson(
      '/v1/auth/profile?user_id=$userId',
      {},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> subscription({
    required String userId,
    required String accessToken,
  }) {
    return _api.postJson(
      '/v1/billing/subscription?user_id=$userId',
      {},
      accessToken: accessToken,
    );
  }
}
