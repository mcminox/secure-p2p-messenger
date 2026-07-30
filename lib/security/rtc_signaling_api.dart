import 'server_api_client.dart';

class RtcSignalingApi {
  RtcSignalingApi({ServerApiClient? api}) : _api = api ?? ServerApiClient();

  final ServerApiClient _api;

  Future<Map<String, dynamic>> fetchIce({
    required String userId,
    required bool activeSubscription,
    required String accessToken,
  }) {
    return _api.postJson(
      '/v1/rtc/ice',
      {
        'user_id': userId,
        'active_subscription': activeSubscription,
      },
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> openPresence({
    required String userId,
    required String nickname,
    required String connectToken,
    required String deviceId,
    required String offerSdp,
    required bool activeSubscription,
    required String accessToken,
  }) {
    return _api.postJson(
      '/v1/rtc/open',
      {
        'user_id': userId,
        'nickname': nickname,
        'connect_token': connectToken,
        'device_id': deviceId,
        'offer_sdp': offerSdp,
        'active_subscription': activeSubscription,
      },
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> findByToken({
    required String requesterUserId,
    required String targetConnectToken,
    required String accessToken,
  }) {
    return _api.postJson(
      '/v1/rtc/find',
      {
        'requester_user_id': requesterUserId,
        'target_connect_token': targetConnectToken,
      },
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> submitAnswer({
    required String sessionId,
    required String secret,
    required String answerSdp,
    required String accessToken,
  }) {
    return _api.postJson(
      '/v1/rtc/answer',
      {
        'session_id': sessionId,
        'secret': secret,
        'answer_sdp': answerSdp,
      },
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> pollAnswer({
    required String sessionId,
    required String secret,
    required String accessToken,
  }) {
    return _api.postJson(
      '/v1/rtc/poll',
      {
        'session_id': sessionId,
        'secret': secret,
      },
      accessToken: accessToken,
    );
  }
}
