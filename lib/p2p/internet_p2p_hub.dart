import 'dart:async';

import 'package:flutter/foundation.dart';

import '../crypto/public_key_codec.dart';
import '../identity/user_identity.dart';
import '../prefs/app_preferences.dart';
import '../security/rtc_signaling_api.dart';
import '../sync/chat_index.dart';
import '../sync/conversation_id.dart';
import '../sync/local_chat_store.dart';
import 'internet_rtc_session.dart';
import 'internet_sync_lane.dart';
import 'rtc_signaling_codec.dart';

class InternetP2pHub extends ChangeNotifier {
  InternetP2pHub({
    required this.identity,
    required this.store,
    this.allowSecureSync,
  });

  final UserIdentity identity;
  final LocalChatStore store;
  final Future<bool> Function()? allowSecureSync;
  final _prefs = AppPreferences();
  final _rtcApi = RtcSignalingApi();

  InternetRtcSession? _session;
  InternetRtcSession? _pendingCaller;
  InternetSyncLane? _lane;
  StreamSubscription<Uint8List>? _sub;
  Timer? _pullTimer;
  String? _activeConversationId;

  bool isLinked(String conversationId) =>
      _activeConversationId == conversationId && _session != null && _session!.isChannelOpen;

  Future<String> createOfferForConversation(String conversationId) async {
    await tearDown();
    final r = await InternetRtcSession.createCaller();
    _pendingCaller = r.session;
    _activeConversationId = conversationId;
    _pendingCaller!.onDisconnected = () {
      unawaited(tearDown());
      notifyListeners();
    };
    return RtcSignalingCodec.buildJson(
      role: 'offer',
      conversationId: conversationId,
      sdp: r.offerSdp,
    );
  }

  Future<void> applyAnswerJson(String rawAnswer) async {
    final p = RtcSignalingCodec.tryParse(rawAnswer);
    if (p == null) throw ArgumentError('Неверный формат SDP-ответа');
    if (p.role != 'answer') throw ArgumentError('Нужен JSON с role: answer');
    if (_pendingCaller == null) throw StateError('Сначала создайте приглашение (offer)');
    if (p.cid != _activeConversationId) throw ArgumentError('Ответ для другого чата');
    await _pendingCaller!.applyAnswerSdp(p.sdp);
    _session = _pendingCaller;
    _pendingCaller = null;
    _session!.onDisconnected = () {
      unawaited(tearDown());
      notifyListeners();
    };
    await _waitChannelOpen();
    await _attachLane(p.cid);
    _armPullTimer();
    notifyListeners();
  }

  Future<String> acceptOfferJson(String rawOffer) async {
    final p = RtcSignalingCodec.tryParse(rawOffer);
    if (p == null) throw ArgumentError('Неверный формат SDP-приглашения');
    if (p.role != 'offer') throw ArgumentError('Нужен JSON с role: offer');
    await tearDown();
    final r = await InternetRtcSession.acceptCallee(offerSdp: p.sdp);
    _session = r.session;
    _activeConversationId = p.cid;
    _session!.onDisconnected = () {
      unawaited(tearDown());
      notifyListeners();
    };
    await _waitChannelOpen();
    await _attachLane(p.cid);
    _armPullTimer();
    notifyListeners();
    return RtcSignalingCodec.buildJson(
      role: 'answer',
      conversationId: p.cid,
      sdp: r.answerSdp,
    );
  }

  Future<void> _waitChannelOpen() async {
    for (var i = 0; i < 120; i++) {
      if (_session?.isChannelOpen == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 125));
    }
    throw StateError(
      'Канал не открылся (симметричный NAT / файрвол). Попробуйте другую сеть или оба в одной Wi‑Fi.',
    );
  }

  Future<void> _attachLane(String conversationId) async {
    await _sub?.cancel();
    _sub = null;
    _lane = null;
    final entries = await store.loadChatEntries();
    ChatListEntry? entry;
    for (final e in entries) {
      if (e.conversationId == conversationId) {
        entry = e;
        break;
      }
    }
    if (entry == null) throw StateError('Чат не найден');
    if (entry.type != ChatType.direct) {
      throw StateError('Интернет-синхронизация только для личных чатов');
    }
    final pk = parseEd25519PublicKeyHex(entry.peerPublicKeyHex ?? '');
    if (pk == null) throw StateError('Нет ключа собеседника');
    final peerFp = ConversationId.fingerprint(pk);
    final lane = InternetSyncLane(
      identity: identity,
      store: store,
      conversationId: conversationId,
      expectedPeerFingerprint: peerFp,
      sendSigned: (b) async {
        final s = _session;
        if (s != null && s.isChannelOpen) await s.sendBytes(b);
      },
      onApplied: () => notifyListeners(),
      allowSecureSync: allowSecureSync,
    );
    await lane.prepare();
    _lane = lane;
    final s = _session;
    if (s == null) return;
    _sub = s.incoming.listen((bytes) {
      unawaited(_lane?.handleIncoming(bytes));
    });
  }

  void _armPullTimer() {
    _pullTimer?.cancel();
    _pullTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      unawaited(_tickPull());
    });
    unawaited(_tickPull());
  }

  Future<void> _tickPull() async {
    if (_lane == null || _session == null || !_session!.isChannelOpen) return;
    try {
      await _lane!.sendPullIfIdle();
    } catch (_) {}
  }

  Future<void> requestImmediateSync(String conversationId) async {
    if (!isLinked(conversationId)) return;
    await _tickPull();
  }

  Future<({String sessionId, String secret})> publishServerRendezvous(String conversationId) async {
    final offerJson = await createOfferForConversation(conversationId);
    final p = RtcSignalingCodec.tryParse(offerJson);
    if (p == null) {
      throw StateError('Невозможно подготовить offer');
    }
    final uid = await _prefs.userId();
    final token = await _prefs.accessToken();
    final nick = await _prefs.nickname();
    final connectToken = await _prefs.connectToken();
    final did = await _prefs.deviceId();
    final sub = await _prefs.hasActiveSubscription();
    if (uid == null || token == null || connectToken == null || did == null) {
      throw StateError('Нет серверной авторизации/токена подключения');
    }
    final open = await _rtcApi.openPresence(
      userId: uid,
      nickname: nick ?? 'User',
      connectToken: connectToken,
      deviceId: did,
      offerSdp: p.sdp,
      activeSubscription: sub,
      accessToken: token,
    );
    return (
      sessionId: open['session_id']?.toString() ?? '',
      secret: open['secret']?.toString() ?? '',
    );
  }

  Future<void> connectViaServerToken({
    required String conversationId,
    required String targetConnectToken,
  }) async {
    final uid = await _prefs.userId();
    final token = await _prefs.accessToken();
    if (uid == null || token == null) {
      throw StateError('Нет серверной авторизации');
    }
    final found = await _rtcApi.findByToken(
      requesterUserId: uid,
      targetConnectToken: targetConnectToken,
      accessToken: token,
    );
    final offer = found['offer_sdp']?.toString();
    final sid = found['session_id']?.toString();
    final secret = found['secret']?.toString();
    if (offer == null || sid == null || secret == null) {
      throw StateError('Сессия не найдена');
    }
    final accepted = await InternetRtcSession.acceptCallee(offerSdp: offer);
    final answer = accepted.answerSdp;
    await _rtcApi.submitAnswer(
      sessionId: sid,
      secret: secret,
      answerSdp: answer,
      accessToken: token,
    );
    await tearDown();
    _session = accepted.session;
    _activeConversationId = conversationId;
    _session!.onDisconnected = () {
      unawaited(tearDown());
      notifyListeners();
    };
    await _waitChannelOpen();
    await _attachLane(conversationId);
    _armPullTimer();
    notifyListeners();
  }

  Future<void> pollServerAnswerAndApply({
    required String conversationId,
    required String sessionId,
    required String secret,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final token = await _prefs.accessToken();
    if (token == null) throw StateError('Нет серверной авторизации');
    final started = DateTime.now();
    while (DateTime.now().difference(started) < timeout) {
      final res = await _rtcApi.pollAnswer(
        sessionId: sessionId,
        secret: secret,
        accessToken: token,
      );
      if (res['status']?.toString() == 'connected') {
        final ans = res['answer_sdp']?.toString();
        if (ans != null && ans.isNotEmpty) {
          await applyAnswerJson(RtcSignalingCodec.buildJson(
            role: 'answer',
            conversationId: conversationId,
            sdp: ans,
          ));
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    throw StateError('Таймаут ожидания ответа RTC');
  }

  Future<void> disconnect() async {
    await tearDown();
    notifyListeners();
  }

  Future<void> tearDown() async {
    _pullTimer?.cancel();
    _pullTimer = null;
    final sub = _sub;
    _sub = null;
    if (sub != null) await sub.cancel();
    _lane = null;
    if (_pendingCaller != null) {
      await _pendingCaller!.dispose();
      _pendingCaller = null;
    }
    if (_session != null) {
      await _session!.dispose();
      _session = null;
    }
    _activeConversationId = null;
  }

  @override
  void dispose() {
    _pullTimer?.cancel();
    _pullTimer = null;
    unawaited(_sub?.cancel());
    _sub = null;
    _lane = null;
    final p = _pendingCaller;
    final s = _session;
    _pendingCaller = null;
    _session = null;
    _activeConversationId = null;
    if (p != null) unawaited(p.dispose());
    if (s != null) unawaited(s.dispose());
    super.dispose();
  }
}
