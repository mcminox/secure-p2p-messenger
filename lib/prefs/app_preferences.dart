import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  static const _kSkipHintEd25519 = 'dart_aut_skip_hint_ed25519';
  static const _kSkipHintX25519 = 'dart_aut_skip_hint_x25519';
  static const _kLastDailyPrivacyUtcDay = 'dart_aut_last_daily_privacy_utc_day';
  static const _kPanicModeEnabled = 'dart_aut_panic_mode_enabled';
  static const _kOnboardingSeen = 'dart_aut_onboarding_seen';
  static const _kPrivacyProfile = 'dart_aut_privacy_profile';
  static const _kPinnedByConversation = 'dart_aut_pinned_message_by_conversation';
  static const _kReactionByMessage = 'dart_aut_reaction_by_message';
  static const _kTrustCheckedAtByConversation = 'dart_aut_trust_checked_at_by_conversation';
  static const _kChatColorByConversation = 'dart_aut_chat_color_by_conversation';
  static const _kSendAvatarInSync = 'dart_aut_send_avatar_in_sync';
  static const _kNotificationsEnabled = 'dart_aut_notifications_enabled';
  static const _kNotificationsByConversation = 'dart_aut_notifications_by_conversation';
  static const _kServerBaseUrl = 'dart_aut_server_base_url';
  static const _kServerPin = 'dart_aut_server_pin';
  static const _kUserId = 'dart_aut_user_id';
  static const _kAccessToken = 'dart_aut_access_token';
  static const _kRefreshToken = 'dart_aut_refresh_token';
  static const _kDeviceId = 'dart_aut_device_id';
  static const _kDevicePubkey = 'dart_aut_device_pubkey';
  static const _kAppBuildFingerprint = 'dart_aut_app_build_fingerprint';
  static const _kLicenseEnforcementEnabled = 'dart_aut_license_enforcement_enabled';
  static const _kNickname = 'dart_aut_nickname';
  static const _kConnectToken = 'dart_aut_connect_token';
  static const _kSubscriptionStatus = 'dart_aut_subscription_status';

  static const privacyStandard = 'standard';
  static const privacyStrict = 'strict';
  static const privacyParanoid = 'paranoid';

  Future<bool> skipHintEd25519() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kSkipHintEd25519) ?? false;
  }

  Future<bool> skipHintX25519() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kSkipHintX25519) ?? false;
  }

  Future<void> setSkipHintEd25519(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSkipHintEd25519, v);
  }

  Future<void> setSkipHintX25519(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSkipHintX25519, v);
  }

  Future<void> resetUiPreferences() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSkipHintEd25519);
    await p.remove(_kSkipHintX25519);
  }

  int _utcDayStamp(DateTime dt) {
    final u = dt.toUtc();
    return u.year * 10000 + u.month * 100 + u.day;
  }

  Future<bool> shouldApplyDailyPrivacyPolicy() async {
    final p = await SharedPreferences.getInstance();
    final today = _utcDayStamp(DateTime.now());
    final last = p.getInt(_kLastDailyPrivacyUtcDay) ?? 0;
    return today != last;
  }

  Future<void> markDailyPrivacyPolicyAppliedNow() async {
    final p = await SharedPreferences.getInstance();
    final today = _utcDayStamp(DateTime.now());
    await p.setInt(_kLastDailyPrivacyUtcDay, today);
  }

  Future<bool> isPanicModeEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kPanicModeEnabled) ?? false;
  }

  Future<void> setPanicModeEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPanicModeEnabled, v);
  }

  Future<bool> onboardingSeen() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kOnboardingSeen) ?? false;
  }

  Future<void> setOnboardingSeen(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnboardingSeen, v);
  }

  Future<String> privacyProfile() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPrivacyProfile) ?? privacyStrict;
  }

  Future<void> setPrivacyProfile(String profile) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrivacyProfile, profile);
    if (profile == privacyParanoid) {
      await p.setBool(_kSendAvatarInSync, false);
    }
  }

  Future<bool> isDailyResetEnabled() async {
    final profile = await privacyProfile();
    return profile != privacyStandard;
  }

  Future<Map<String, String>> _readMapStringString(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return j.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMapStringString(String key, Map<String, String> value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode(value));
  }

  Future<String?> pinnedMessageId(String conversationId) async {
    final m = await _readMapStringString(_kPinnedByConversation);
    return m[conversationId];
  }

  Future<void> setPinnedMessageId(String conversationId, String? logicalId) async {
    final m = await _readMapStringString(_kPinnedByConversation);
    if (logicalId == null || logicalId.isEmpty) {
      m.remove(conversationId);
    } else {
      m[conversationId] = logicalId;
    }
    await _writeMapStringString(_kPinnedByConversation, m);
  }

  Future<String?> reactionForMessage(String key) async {
    final m = await _readMapStringString(_kReactionByMessage);
    return m[key];
  }

  Future<void> setReactionForMessage(String key, String? reaction) async {
    final m = await _readMapStringString(_kReactionByMessage);
    if (reaction == null || reaction.isEmpty) {
      m.remove(key);
    } else {
      m[key] = reaction;
    }
    await _writeMapStringString(_kReactionByMessage, m);
  }

  Future<void> markTrustCheckedNow(String conversationId) async {
    final m = await _readMapStringString(_kTrustCheckedAtByConversation);
    m[conversationId] = DateTime.now().toUtc().toIso8601String();
    await _writeMapStringString(_kTrustCheckedAtByConversation, m);
  }

  Future<String?> trustCheckedAt(String conversationId) async {
    final m = await _readMapStringString(_kTrustCheckedAtByConversation);
    return m[conversationId];
  }

  Future<int?> chatColor(String conversationId) async {
    final m = await _readMapStringString(_kChatColorByConversation);
    final raw = m[conversationId];
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  Future<void> setChatColor(String conversationId, int? colorValue) async {
    final m = await _readMapStringString(_kChatColorByConversation);
    if (colorValue == null) {
      m.remove(conversationId);
    } else {
      m[conversationId] = '$colorValue';
    }
    await _writeMapStringString(_kChatColorByConversation, m);
  }

  Future<bool> sendAvatarInSync() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kSendAvatarInSync) ?? true;
  }

  Future<void> setSendAvatarInSync(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSendAvatarInSync, v);
  }

  Future<bool> notificationsEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kNotificationsEnabled) ?? true;
  }

  Future<void> setNotificationsEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kNotificationsEnabled, v);
  }

  Future<bool> notificationsEnabledForConversation(String conversationId) async {
    final m = await _readMapStringString(_kNotificationsByConversation);
    final raw = m[conversationId];
    if (raw == null) return true;
    return raw == '1';
  }

  Future<void> setNotificationsEnabledForConversation(
    String conversationId,
    bool enabled,
  ) async {
    final m = await _readMapStringString(_kNotificationsByConversation);
    m[conversationId] = enabled ? '1' : '0';
    await _writeMapStringString(_kNotificationsByConversation, m);
  }

  Future<String> serverBaseUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kServerBaseUrl) ?? '';
  }

  Future<void> setServerBaseUrl(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServerBaseUrl, value.trim());
  }

  Future<String> serverPin() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kServerPin) ?? '';
  }

  Future<void> setServerPin(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServerPin, value.trim());
  }

  Future<String?> userId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kUserId);
  }

  Future<void> setUserId(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUserId, value);
  }

  Future<String?> accessToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kAccessToken);
  }

  Future<void> setAccessToken(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccessToken, value);
  }

  Future<String?> refreshToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kRefreshToken);
  }

  Future<void> setRefreshToken(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRefreshToken, value);
  }

  Future<String?> deviceId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kDeviceId);
  }

  Future<void> setDeviceId(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDeviceId, value);
  }

  Future<String?> devicePubkey() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kDevicePubkey);
  }

  Future<void> setDevicePubkey(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDevicePubkey, value);
  }

  Future<String?> appBuildFingerprint() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kAppBuildFingerprint);
  }

  Future<void> setAppBuildFingerprint(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAppBuildFingerprint, value);
  }

  Future<bool> licenseEnforcementEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kLicenseEnforcementEnabled) ?? true;
  }

  Future<void> setLicenseEnforcementEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kLicenseEnforcementEnabled, value);
  }

  Future<String?> nickname() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kNickname);
  }

  Future<void> setNickname(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNickname, value);
  }

  Future<String?> connectToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kConnectToken);
  }

  Future<void> setConnectToken(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kConnectToken, value);
  }

  Future<String> subscriptionStatus() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kSubscriptionStatus) ?? 'trial';
  }

  Future<void> setSubscriptionStatus(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSubscriptionStatus, value);
  }

  Future<bool> hasActiveSubscription() async {
    final s = await subscriptionStatus();
    return s == 'active' || s == 'grace';
  }
}
