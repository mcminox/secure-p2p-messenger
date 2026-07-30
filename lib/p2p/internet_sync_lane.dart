import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../crypto/public_key_codec.dart';
import '../debug/debug_hub.dart';
import '../identity/user_identity.dart';
import '../prefs/app_preferences.dart';
import '../profile/avatar_store.dart';
import '../sync/chat_index.dart';
import '../sync/conversation_id.dart';
import '../sync/local_chat_store.dart';
import '../sync/models.dart';
import '../sync/p2p_sync_coordinator.dart';
import '../util/local_notifications.dart';
import 'json_frag_buffer.dart';
import 'lan_install_id.dart';
import 'lan_signed_packet.dart';
import 'p2p_constants.dart';

class InternetSyncLane {
  InternetSyncLane({
    required this.identity,
    required this.store,
    required this.conversationId,
    required this.expectedPeerFingerprint,
    required this.sendSigned,
    this.onApplied,
    this.allowSecureSync,
  });

  final UserIdentity identity;
  final LocalChatStore store;
  final String conversationId;
  final String expectedPeerFingerprint;
  final Future<void> Function(Uint8List packet) sendSigned;
  final void Function()? onApplied;
  final Future<bool> Function()? allowSecureSync;
  final _prefs = AppPreferences();

  String _installId = '';
  final Map<String, JsonFragBuffer> _frag = {};
  String? _openPullConnId;
  Timer? _pullTimeout;

  Future<void> prepare() async {
    _installId = await LanInstallId.getOrCreate();
  }

  Map<String, dynamic> _stamp(Map<String, dynamic> inner) {
    if ((inner['k'] as String?) == 'frag') return inner;
    return {...inner, 'did': _installId};
  }

  Future<void> _emitSigned(Map<String, dynamic> inner) async {
    final stamped = _stamp(inner);
    final raw = utf8.encode(jsonEncode(stamped));
    if (raw.length <= 48000) {
      final packet = await LanSignedPacket.encodeAndSign(inner: stamped, signer: identity.ed25519);
      await sendSigned(packet);
      return;
    }
    final rid = const Uuid().v4();
    const chunkSize = 700;
    final n = (raw.length + chunkSize - 1) ~/ chunkSize;
    for (var i = 0; i < n; i++) {
      final start = i * chunkSize;
      final end = start + chunkSize > raw.length ? raw.length : start + chunkSize;
      final fragInner = <String, dynamic>{
        'k': 'frag',
        'rid': rid,
        'i': i,
        'n': n,
        'd': base64Encode(raw.sublist(start, end)),
      };
      final packet = await LanSignedPacket.encodeAndSign(inner: fragInner, signer: identity.ed25519);
      await sendSigned(packet);
    }
  }

  Future<void> sendPullIfIdle() async {
    if (allowSecureSync != null && !await allowSecureSync!()) {
      DebugHub.instance.log('webrtc sync blocked by license gate');
      return;
    }
    if (_openPullConnId != null) return;
    final target = await _directEntryForPeerFp(expectedPeerFingerprint);
    if (target == null || target.conversationId != conversationId) return;
    final state = await store.loadState(target.conversationId);
    if (state.kind != ConversationKind.direct) return;
    final myPub = await identity.ed25519PublicKey();
    final myFp = ConversationId.fingerprint(myPub);
    final coord = P2pSyncCoordinator(store);
    final pull = coord.buildPullRequest(state: state, requesterFingerprint: myFp);
    final inner = <String, dynamic>{
      'k': 'sync_req',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'cid': target.conversationId,
      'pull': pull,
    };
    _openPullConnId = DebugHub.instance.openConnection(
      'WebRTC sync → $expectedPeerFingerprint',
      id: 'rtc-pull-${DateTime.now().microsecondsSinceEpoch}',
    );
    _pullTimeout?.cancel();
    _pullTimeout = Timer(const Duration(seconds: 45), () {
      _openPullConnId = null;
    });
    await _emitSigned(inner);
  }

  Future<void> handleIncoming(Uint8List data) async {
    final decoded = await LanSignedPacket.verifyAndDecodeWithKey(data);
    if (decoded == null) return;
    final inner = decoded.inner;
    final pk = decoded.pk;
    final senderFp = ConversationId.fingerprint(pk);
    if (senderFp != expectedPeerFingerprint) {
      DebugHub.instance.log('webrtc: чужой отпечаток');
      return;
    }
    final myPub = await identity.ed25519PublicKey();
    if (ed25519PublicKeysEqual(pk, myPub)) {
      final remoteDid = inner['did'];
      final remoteStr = remoteDid is String && remoteDid.isNotEmpty ? remoteDid : LanInstallId.legacyUnknown;
      if (remoteStr == _installId) return;
    }
    final k = inner['k'] as String?;
    if (k == 'frag') {
      await _handleFrag(inner, pk);
      return;
    }
    await _dispatchInner(inner, pk);
  }

  Future<void> _handleFrag(Map<String, dynamic> inner, SimplePublicKey pk) async {
    final rid = inner['rid'] as String?;
    final i = (inner['i'] as num?)?.toInt();
    final n = (inner['n'] as num?)?.toInt();
    final d = inner['d'] as String?;
    if (rid == null || i == null || n == null || d == null || n <= 0 || i < 0 || i >= n) {
      return;
    }
    var buf = _frag[rid];
    if (buf == null || buf.n != n) {
      buf = JsonFragBuffer(n);
      _frag[rid] = buf;
    }
    if (!buf.add(i, d)) return;
    final s = buf.assembleUtf8();
    _frag.remove(rid);
    if (s == null) return;
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    await _dispatchInner(decoded, pk);
  }

  Future<void> _dispatchInner(Map<String, dynamic> inner, SimplePublicKey senderPk) async {
    final k = inner['k'] as String?;
    if (k == 'sync_req') {
      await _handleSyncRequest(inner, senderPk);
      return;
    }
    if (k == 'sync_resp') {
      await _handleSyncResponse(inner, senderPk);
      return;
    }
  }

  Future<void> _handleSyncRequest(Map<String, dynamic> inner, SimplePublicKey senderPk) async {
    if (allowSecureSync != null && !await allowSecureSync!()) {
      DebugHub.instance.log('webrtc incoming sync blocked by license gate');
      return;
    }
    final senderFp = ConversationId.fingerprint(senderPk);
    final cid = inner['cid'] as String?;
    final pullRaw = inner['pull'];
    if (cid == null || cid != conversationId || pullRaw is! Map) return;
    final pull = Map<String, dynamic>.from(pullRaw);
    if ((pull['requester_fingerprint'] as String?) != senderFp) {
      DebugHub.instance.log('webrtc sync_req: подпись requester');
      return;
    }

    final entry = await _entryByCid(cid);
    if (entry == null) return;

    ConversationSyncState state;
    try {
      state = await store.loadState(cid);
    } catch (_) {
      return;
    }

    if (state.kind != ConversationKind.direct || state.peerFingerprint != senderFp) {
      DebugHub.instance.log('webrtc sync_req: peer mismatch');
      return;
    }

    final connId = DebugHub.instance.openConnection('WebRTC входящий pull $cid');

    if (!entry.trustIncomingSync) {
      final myPub = await identity.ed25519PublicKey();
      final myFp = ConversationId.fingerprint(myPub);
      final coord = P2pSyncCoordinator(store);
      final packets = await coord.responderHandlePullRequest(
        responderState: state,
        responderFingerprint: myFp,
        request: pull,
        allow: false,
        denyReason: 'Включите «Доверять входящей синхронизации» в чате',
        maxMessages: P2pConstants.maxMessagesPerBatch,
      );
      await _emitSigned(<String, dynamic>{
        'k': 'sync_resp',
        'ts': DateTime.now().millisecondsSinceEpoch,
        'cid': cid,
        'packets': packets,
        if (await _prefs.sendAvatarInSync()) 'avatar_b64': await AvatarStore.instance.myAvatarB64OrNull(),
      });
      DebugHub.instance.closeConnection(connId, ok: false, suspicious: false, detail: 'Нет доверия');
      return;
    }

    final myPub = await identity.ed25519PublicKey();
    final myFp = ConversationId.fingerprint(myPub);
    final coord = P2pSyncCoordinator(store);
    final packets = await coord.responderHandlePullRequest(
      responderState: state,
      responderFingerprint: myFp,
      request: pull,
      allow: true,
      maxMessages: P2pConstants.maxMessagesPerBatch,
    );

    await _emitSigned(<String, dynamic>{
      'k': 'sync_resp',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'cid': cid,
      'packets': packets,
      if (await _prefs.sendAvatarInSync()) 'avatar_b64': await AvatarStore.instance.myAvatarB64OrNull(),
    });
    DebugHub.instance.closeConnection(connId, ok: true);
  }

  Future<void> _handleSyncResponse(Map<String, dynamic> inner, SimplePublicKey senderPk) async {
    final senderFp = ConversationId.fingerprint(senderPk);
    final cid = inner['cid'] as String?;
    final packetsRaw = inner['packets'];
    final avatarB64 = inner['avatar_b64'] as String?;
    if (cid == null || cid != conversationId || packetsRaw is! List) return;

    final connId = _openPullConnId;
    _openPullConnId = null;
    _pullTimeout?.cancel();
    _pullTimeout = null;

    ConversationSyncState state;
    try {
      state = await store.loadState(cid);
    } catch (_) {
      if (connId != null) {
        DebugHub.instance.closeConnection(connId, ok: false, suspicious: true, detail: 'Нет состояния');
      }
      return;
    }

    if (state.kind != ConversationKind.direct || state.peerFingerprint != senderFp) {
      if (connId != null) {
        DebugHub.instance.closeConnection(connId, ok: false, suspicious: true, detail: 'Неверный peer');
      }
      return;
    }
    if (avatarB64 != null && avatarB64.isNotEmpty) {
      await AvatarStore.instance.savePeerAvatarB64(senderFp, avatarB64);
    }

    final packets = <Map<String, dynamic>>[];
    for (final p in packetsRaw) {
      if (p is Map<String, dynamic>) {
        packets.add(p);
      } else if (p is Map) {
        packets.add(Map<String, dynamic>.from(p));
      }
    }
    try {
      final existing = await store.loadMessagesUnsortedRaw(cid);
      final existingIds = existing.map((e) => ChatMessageRecord.fromJson(e).logicalId).toSet();
      final incoming = _collectNewIncomingBodies(
        packets: packets,
        senderFingerprint: senderFp,
        existingLogicalIds: existingIds,
      );
      final coord = P2pSyncCoordinator(store);
      await coord.requesterApplyPackets(state: state, packets: packets);
      if (incoming.isNotEmpty) {
        final entry = await _entryByCid(cid);
        final count = incoming.length;
        final body = count == 1 ? incoming.last : 'Новых сообщений: $count';
        await LocalNotifications.instance.showIncomingMessage(
          conversationId: cid,
          title: entry?.title ?? 'Новый чат',
          body: _notificationPreview(body),
        );
      }
      if (connId != null) {
        DebugHub.instance.closeConnection(connId, ok: true);
      }
      onApplied?.call();
    } catch (e) {
      if (connId != null) {
        DebugHub.instance.closeConnection(connId, ok: false, suspicious: true, detail: '$e');
      }
    }
  }

  List<String> _collectNewIncomingBodies({
    required List<Map<String, dynamic>> packets,
    required String senderFingerprint,
    required Set<String> existingLogicalIds,
  }) {
    final out = <String>[];
    for (final p in packets) {
      if (p['type'] != 'message_batch') continue;
      final raw = p['messages'];
      if (raw is! List) continue;
      for (final it in raw) {
        if (it is! Map) continue;
        final rec = ChatMessageRecord.fromJson(Map<String, dynamic>.from(it));
        if (rec.senderFingerprint != senderFingerprint) continue;
        if (existingLogicalIds.contains(rec.logicalId)) continue;
        out.add(rec.body);
      }
    }
    return out;
  }

  String _notificationPreview(String body) {
    final t = body.trimLeft();
    if (!t.startsWith('{')) return body;
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['k'] == 'att') {
        return 'Вложение: ${j['name'] ?? 'файл'}';
      }
    } catch (_) {}
    return body;
  }

  Future<ChatListEntry?> _directEntryForPeerFp(String peerFp) async {
    final entries = await store.loadChatEntries();
    for (final e in entries) {
      if (e.type != ChatType.direct) continue;
      final pk = parseEd25519PublicKeyHex(e.peerPublicKeyHex ?? '');
      if (pk == null) continue;
      if (ConversationId.fingerprint(pk) == peerFp) return e;
    }
    return null;
  }

  Future<ChatListEntry?> _entryByCid(String cid) async {
    final entries = await store.loadChatEntries();
    try {
      return entries.firstWhere((e) => e.conversationId == cid);
    } catch (_) {
      return null;
    }
  }
}
