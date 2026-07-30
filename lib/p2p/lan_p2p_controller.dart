import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../crypto/conversation_crypto.dart';
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

class LanP2pController extends ChangeNotifier with WidgetsBindingObserver {
  LanP2pController({
    required this.identity,
    required this.store,
  });

  final UserIdentity identity;
  final LocalChatStore store;
  final _prefs = AppPreferences();

  RawDatagramSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _uiTimer;
  final Map<String, DateTime> _lastHeard = {};
  final Map<String, InternetAddress> _addrByEndpoint = {};
  final Map<String, DateTime> _lastPullAt = {};
  final Map<String, String> _openPullByEndpoint = {};
  final Map<String, JsonFragBuffer> _frag = {};
  Set<String>? _interestCache;
  DateTime? _interestCacheAt;
  bool _running = false;
  bool _appPaused = false;
  String _installId = '';

  bool Function(String conversationId)? internetLinked;

  void invalidateInterestCache() {
    _interestCache = null;
    _interestCacheAt = null;
  }

  static bool _endpointKeyIsForPeerFp(String endpointKey, String peerFp) {
    if (endpointKey == peerFp) return true;
    return endpointKey.startsWith('$peerFp|');
  }

  String _endpointKey(SimplePublicKey pk, Map<String, dynamic> inner) {
    final fp = ConversationId.fingerprint(pk);
    final did = inner['did'];
    final didStr = did is String && did.isNotEmpty ? did : LanInstallId.legacyUnknown;
    return '$fp|$didStr';
  }

  Map<String, dynamic> _stampOutbound(Map<String, dynamic> inner) {
    if ((inner['k'] as String?) == 'frag') return inner;
    return {...inner, 'did': _installId};
  }

  void _sendPayloadBytes(Uint8List bytes) {
    if (_socket == null || !_running) return;
    try {
      _sendRaw(bytes, InternetAddress(P2pConstants.multicastHost));
      _sendRaw(bytes, InternetAddress('255.255.255.255'));
    } catch (e) {
      debugPrint('P2P multicast/broadcast: $e');
    }
  }

  void _sendRaw(Uint8List bytes, InternetAddress addr) {
    try {
      _socket?.send(bytes, addr, P2pConstants.udpPort);
    } catch (e) {
      debugPrint('P2P send → $addr: $e');
    }
  }

  bool get isRunning => _running;

  DateTime? lastHeardOf(String peerFingerprint) {
    DateTime? best;
    for (final e in _lastHeard.entries) {
      if (!_endpointKeyIsForPeerFp(e.key, peerFingerprint)) continue;
      if (best == null || e.value.isAfter(best)) best = e.value;
    }
    return best;
  }

  bool isPeerOnline(String peerFingerprint) {
    final t = lastHeardOf(peerFingerprint);
    if (t == null) return false;
    return DateTime.now().difference(t) <= P2pConstants.onlineIfHeardWithin;
  }

  bool isDirectChatVisible(ChatListEntry e) {
    if (e.type != ChatType.direct) return true;
    if (internetLinked != null && internetLinked!(e.conversationId)) return true;
    final pk = parseEd25519PublicKeyHex(e.peerPublicKeyHex ?? '');
    if (pk == null) return true;
    final fp = ConversationId.fingerprint(pk);
    final last = lastHeardOf(fp);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last == null) {
      return now - e.createdAtMillis < P2pConstants.graceIfNeverSeen.inMilliseconds;
    }
    return DateTime.now().difference(last) <= P2pConstants.hideChatIfSilentFor;
  }

  bool isHiddenFromMainList(ChatListEntry e) {
    if (e.userPinnedHidden) return true;
    if (e.type == ChatType.direct && !isDirectChatVisible(e)) return true;
    return false;
  }

  Future<void> start() async {
    if (_running) return;
    _installId = await LanInstallId.getOrCreate();
    WidgetsBinding.instance.addObserver(this);
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        P2pConstants.udpPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      try {
        socket.joinMulticast(InternetAddress(P2pConstants.multicastHost));
      } catch (e) {
        debugPrint('P2P joinMulticast: $e');
      }
    } catch (e) {
      debugPrint('P2P bind failed (порт ${P2pConstants.udpPort}?): $e');
      WidgetsBinding.instance.removeObserver(this);
      return;
    }
    _socket = socket;
    _running = true;
    socket.listen(_onSocketEvent, onError: (e) => debugPrint('P2P socket: $e'));
    _heartbeatTimer = Timer.periodic(P2pConstants.heartbeatInterval, (_) {
      unawaited(_sendHeartbeat());
    });
    _uiTimer = Timer.periodic(const Duration(seconds: 2), (_) => notifyListeners());
    unawaited(_sendHeartbeat());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appPaused = state != AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    if (_running) {
      _running = false;
      WidgetsBinding.instance.removeObserver(this);
      _heartbeatTimer?.cancel();
      _uiTimer?.cancel();
      _heartbeatTimer = null;
      _uiTimer = null;
      try {
        _socket?.close();
      } catch (_) {}
      _socket = null;
      _lastHeard.clear();
      _addrByEndpoint.clear();
      _lastPullAt.clear();
      _openPullByEndpoint.clear();
      _frag.clear();
      invalidateInterestCache();
    }
    super.dispose();
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    unawaited(_handleDatagram(dg.data, dg.address));
  }

  Future<void> _sendHeartbeat() async {
    if (_socket == null || !_running || _appPaused || _installId.isEmpty) return;
    try {
      final inner = _stampOutbound(<String, dynamic>{
        'k': 'hb',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      final bytes = await LanSignedPacket.encodeAndSign(inner: inner, signer: identity.ed25519);
      _sendPayloadBytes(bytes);
    } catch (e) {
      debugPrint('P2P heartbeat: $e');
    }
  }

  Future<Set<String>> _interestFingerprints() async {
    final now = DateTime.now();
    if (_interestCache != null &&
        _interestCacheAt != null &&
        now.difference(_interestCacheAt!) < const Duration(seconds: 8)) {
      return _interestCache!;
    }
    final entries = await store.loadChatEntries();
    final out = <String>{};
    for (final e in entries) {
      if (e.type == ChatType.direct) {
        final pk = parseEd25519PublicKeyHex(e.peerPublicKeyHex ?? '');
        if (pk != null) out.add(ConversationId.fingerprint(pk));
      } else if (e.type == ChatType.group) {
        for (final m in e.members ?? []) {
          final pk = parseEd25519PublicKeyHex(m.publicKeyHex);
          if (pk != null) out.add(ConversationId.fingerprint(pk));
        }
      }
    }
    _interestCache = out;
    _interestCacheAt = now;
    return out;
  }

  Future<void> _handleDatagram(Uint8List data, InternetAddress addr) async {
    final decoded = await LanSignedPacket.verifyAndDecodeWithKey(data);
    if (decoded == null) {
      DebugHub.instance.log('Пакет с $addr: подпись не сошлась');
      return;
    }
    final inner = decoded.inner;
    final pk = decoded.pk;

    final k = inner['k'] as String?;
    if (k == 'frag') {
      await _handleFrag(inner, pk, addr);
      return;
    }

    await _dispatchInner(inner, pk, addr);
  }

  Future<void> _handleFrag(Map<String, dynamic> inner, SimplePublicKey pk, InternetAddress addr) async {
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
      DebugHub.instance.log('Фрагменты $rid: битый JSON');
      return;
    }
    await _dispatchInner(decoded, pk, addr);
  }

  Future<void> _dispatchInner(
    Map<String, dynamic> inner,
    SimplePublicKey senderPk,
    InternetAddress addr,
  ) async {
    final myPub = await identity.ed25519PublicKey();
    if (ed25519PublicKeysEqual(senderPk, myPub)) {
      final remoteDid = inner['did'];
      final remoteStr = remoteDid is String && remoteDid.isNotEmpty ? remoteDid : LanInstallId.legacyUnknown;
      if (remoteStr == _installId) return;
    }

    final senderFp = ConversationId.fingerprint(senderPk);
    final endpoint = _endpointKey(senderPk, inner);
    final k = inner['k'] as String?;

    if (k == 'hb') {
      final interest = await _interestFingerprints();
      if (!interest.contains(senderFp)) return;
      _lastHeard[endpoint] = DateTime.now();
      _addrByEndpoint[endpoint] = addr;
      notifyListeners();
      unawaited(_maybePullFrom(senderFp));
      return;
    }
    if (k == 'sync_req') {
      await _handleSyncRequest(inner, senderPk, addr);
      return;
    }
    if (k == 'sync_resp') {
      await _handleSyncResponse(inner, senderPk);
      notifyListeners();
      return;
    }
    if (k == 'group_push') {
      await _handleGroupPush(inner, senderPk);
      notifyListeners();
      return;
    }
  }

  Future<void> _sendSignedInnerTo(Map<String, dynamic> inner, InternetAddress addr) async {
    if (_socket == null || !_running || _installId.isEmpty) return;
    final stamped = _stampOutbound(inner);
    final json = jsonEncode(stamped);
    final bytes = utf8.encode(json);
    if (bytes.length <= 900) {
      final packet = await LanSignedPacket.encodeAndSign(inner: stamped, signer: identity.ed25519);
      _sendRaw(packet, addr);
      return;
    }
    final rid = const Uuid().v4();
    const chunkSize = 700;
    final n = (bytes.length + chunkSize - 1) ~/ chunkSize;
    for (var i = 0; i < n; i++) {
      final start = i * chunkSize;
      final end = start + chunkSize > bytes.length ? bytes.length : start + chunkSize;
      final fragInner = <String, dynamic>{
        'k': 'frag',
        'rid': rid,
        'i': i,
        'n': n,
        'd': base64Encode(bytes.sublist(start, end)),
      };
      final packet = await LanSignedPacket.encodeAndSign(inner: fragInner, signer: identity.ed25519);
      _sendRaw(packet, addr);
    }
  }

  Future<void> _sendSignedInnerMulticast(Map<String, dynamic> inner) async {
    if (_socket == null || !_running || _installId.isEmpty) return;
    final stamped = _stampOutbound(inner);
    final json = jsonEncode(stamped);
    final raw = utf8.encode(json);
    if (raw.length <= 900) {
      final packet = await LanSignedPacket.encodeAndSign(inner: stamped, signer: identity.ed25519);
      _sendPayloadBytes(packet);
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
      _sendPayloadBytes(packet);
    }
  }

  Future<void> multicastGroupPush(String conversationId, List<Map<String, dynamic>> messageMaps) async {
    if (messageMaps.isEmpty) return;
    final entry = await _entryByCid(conversationId);
    if (entry == null || entry.type != ChatType.group) return;
    final envelopes = await _groupKeyEnvelopesForBroadcast(entry);
    final inner = <String, dynamic>{
      'k': 'group_push',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'cid': conversationId,
      'maps': messageMaps,
      if (envelopes.isNotEmpty) 'group_key_envelopes': envelopes,
    };
    await _sendSignedInnerMulticast(inner);
  }

  Future<List<Map<String, dynamic>>> _groupKeyEnvelopesForBroadcast(ChatListEntry entry) async {
    final key = await store.getGroupMessageKey(entry.conversationId);
    if (key == null) return const [];
    final senderEd = await identity.ed25519PublicKey();
    final senderFp = ConversationId.fingerprint(senderEd);
    final senderXPub = await identity.x25519PublicKey();
    final out = <Map<String, dynamic>>[];
    for (final m in entry.members ?? const <GroupMemberEntry>[]) {
      final ed = parseEd25519PublicKeyHex(m.publicKeyHex);
      final x = parseX25519PublicKeyHex(m.x25519PublicKeyHex);
      if (ed == null || x == null) continue;
      if (ed25519PublicKeysEqual(ed, senderEd)) continue;
      final recipientFp = ConversationId.fingerprint(ed);
      out.add(
        await ConversationCrypto.wrapGroupKeyForRecipient(
          groupKey: key,
          senderX25519: identity.x25519Static,
          senderX25519Public: senderXPub,
          recipientX25519Public: x,
          conversationId: entry.conversationId,
          senderFingerprint: senderFp,
          recipientFingerprint: recipientFp,
        ),
      );
    }
    return out;
  }

  Future<void> _maybePullFrom(String peerFp) async {
    for (final e in _addrByEndpoint.entries) {
      if (!_endpointKeyIsForPeerFp(e.key, peerFp)) continue;
      final endpointKey = e.key;
      final last = _lastPullAt[endpointKey];
      if (last != null && DateTime.now().difference(last) < P2pConstants.minSyncGap) continue;
      final addr = _addrByEndpoint[endpointKey];
      if (addr == null) continue;
      _lastPullAt[endpointKey] = DateTime.now();
      try {
        await _sendPullRequest(peerFp, endpointKey, addr);
      } catch (err) {
        debugPrint('P2P pull: $err');
      }
    }
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

  bool _groupHasMember(ChatListEntry entry, String edFingerprint) {
    for (final m in entry.members ?? []) {
      final pk = parseEd25519PublicKeyHex(m.publicKeyHex);
      if (pk != null && ConversationId.fingerprint(pk) == edFingerprint) return true;
    }
    return false;
  }

  Future<void> _sendPullRequest(String peerFp, String remoteEndpointKey, InternetAddress addr) async {
    final target = await _directEntryForPeerFp(peerFp);
    if (target == null) return;
    final state = await store.loadState(target.conversationId);
    if (state.kind != ConversationKind.direct) return;
    final myPub = await identity.ed25519PublicKey();
    final myFp = ConversationId.fingerprint(myPub);
    final coord = P2pSyncCoordinator(store);
    final pull = coord.buildPullRequest(state: state, requesterFingerprint: myFp);
    final inner = _stampOutbound(<String, dynamic>{
      'k': 'sync_req',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'cid': target.conversationId,
      'pull': pull,
    });
    final connId = DebugHub.instance.openConnection(
      'Запрос синхр. → $remoteEndpointKey',
      id: 'pull-$remoteEndpointKey-${DateTime.now().microsecondsSinceEpoch}',
    );
    _openPullByEndpoint[remoteEndpointKey] = connId;
    final bytes = await LanSignedPacket.encodeAndSign(inner: inner, signer: identity.ed25519);
    _sendRaw(bytes, addr);
  }

  Future<void> _handleSyncRequest(
    Map<String, dynamic> inner,
    SimplePublicKey senderPk,
    InternetAddress replyAddr,
  ) async {
    final senderFp = ConversationId.fingerprint(senderPk);
    final cid = inner['cid'] as String?;
    final pullRaw = inner['pull'];
    if (cid == null || pullRaw is! Map) return;
    final pull = Map<String, dynamic>.from(pullRaw);
    if ((pull['requester_fingerprint'] as String?) != senderFp) {
      DebugHub.instance.log('sync_req: подозрительный requester_fingerprint');
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

    if (state.kind == ConversationKind.direct) {
      if (state.peerFingerprint != senderFp) {
        DebugHub.instance.log('sync_req: peer mismatch для $cid');
        return;
      }
    } else {
      if (!_groupHasMember(entry, senderFp)) {
        DebugHub.instance.log('sync_req: не участник группы $cid');
        return;
      }
    }

    final connId = DebugHub.instance.openConnection('Входящий pull $cid от $senderFp');

    Map<String, dynamic>? groupEnvelopeForRequester;
    if (state.kind == ConversationKind.group) {
      groupEnvelopeForRequester = await _groupKeyEnvelopeForRequester(entry, senderFp);
    }

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
      await _sendSignedInnerTo(
        <String, dynamic>{
          'k': 'sync_resp',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'cid': cid,
          'packets': packets,
          if (state.kind == ConversationKind.direct && await _prefs.sendAvatarInSync())
            'avatar_b64': await AvatarStore.instance.myAvatarB64OrNull(),
          if (groupEnvelopeForRequester != null) 'group_key_envelope': groupEnvelopeForRequester,
        },
        replyAddr,
      );
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

    await _sendSignedInnerTo(
      <String, dynamic>{
        'k': 'sync_resp',
        'ts': DateTime.now().millisecondsSinceEpoch,
        'cid': cid,
        'packets': packets,
        if (state.kind == ConversationKind.direct && await _prefs.sendAvatarInSync())
          'avatar_b64': await AvatarStore.instance.myAvatarB64OrNull(),
        if (groupEnvelopeForRequester != null) 'group_key_envelope': groupEnvelopeForRequester,
      },
      replyAddr,
    );
    DebugHub.instance.closeConnection(connId, ok: true);
  }

  Future<void> _handleSyncResponse(Map<String, dynamic> inner, SimplePublicKey senderPk) async {
    final senderFp = ConversationId.fingerprint(senderPk);
    final senderEndpoint = _endpointKey(senderPk, inner);
    final cid = inner['cid'] as String?;
    final packetsRaw = inner['packets'];
    if (cid == null || packetsRaw is! List) return;
    final avatarB64 = inner['avatar_b64'] as String?;

    final connId = _openPullByEndpoint.remove(senderEndpoint);

    ConversationSyncState state;
    try {
      state = await store.loadState(cid);
    } catch (_) {
      if (connId != null) {
        DebugHub.instance.closeConnection(connId, ok: false, suspicious: true, detail: 'Нет состояния');
      }
      return;
    }

    if (state.kind == ConversationKind.direct) {
      if (state.peerFingerprint != senderFp) {
        DebugHub.instance.log('sync_resp: неверный отправитель');
        if (connId != null) {
          DebugHub.instance.closeConnection(connId, ok: false, suspicious: true, detail: 'Неверный peer');
        }
        return;
      }
      if (avatarB64 != null && avatarB64.isNotEmpty) {
        await AvatarStore.instance.savePeerAvatarB64(senderFp, avatarB64);
      }
    } else {
      final entry = await _entryByCid(cid);
      if (entry == null || !_groupHasMember(entry, senderFp)) {
        if (connId != null) {
          DebugHub.instance.closeConnection(connId, ok: false, suspicious: true, detail: 'Не участник');
        }
        return;
      }
      final envRaw = inner['group_key_envelope'];
      if (envRaw is Map) {
        try {
          final myPub = await identity.ed25519PublicKey();
          final myFp = ConversationId.fingerprint(myPub);
          final key = await ConversationCrypto.unwrapGroupKeyFromEnvelope(
            envelope: Map<String, dynamic>.from(envRaw),
            recipientX25519: identity.x25519Static,
            conversationId: cid,
            senderFingerprint: senderFp,
            recipientFingerprint: myFp,
          );
          await store.setGroupMessageKey(cid, key);
        } catch (_) {}
      }
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
    } catch (e) {
      if (connId != null) {
        DebugHub.instance.closeConnection(connId, ok: false, suspicious: true, detail: '$e');
      }
    }
  }

  Future<Map<String, dynamic>?> _groupKeyEnvelopeForRequester(
    ChatListEntry entry,
    String requesterFp,
  ) async {
    if (entry.type != ChatType.group) return null;
    final requester = () {
      for (final m in entry.members ?? const <GroupMemberEntry>[]) {
        final ed = parseEd25519PublicKeyHex(m.publicKeyHex);
        if (ed == null) continue;
        if (ConversationId.fingerprint(ed) == requesterFp) return m;
      }
      return null;
    }();
    if (requester == null) return null;
    final requesterX = parseX25519PublicKeyHex(requester.x25519PublicKeyHex);
    if (requesterX == null) return null;
    final key = await store.getGroupMessageKey(entry.conversationId);
    if (key == null) return null;
    final myEd = await identity.ed25519PublicKey();
    final myFp = ConversationId.fingerprint(myEd);
    final myXPub = await identity.x25519PublicKey();
    return ConversationCrypto.wrapGroupKeyForRecipient(
      groupKey: key,
      senderX25519: identity.x25519Static,
      senderX25519Public: myXPub,
      recipientX25519Public: requesterX,
      conversationId: entry.conversationId,
      senderFingerprint: myFp,
      recipientFingerprint: requesterFp,
    );
  }

  Future<void> _handleGroupPush(Map<String, dynamic> inner, SimplePublicKey senderPk) async {
    final senderFp = ConversationId.fingerprint(senderPk);
    final cid = inner['cid'] as String?;
    final mapsRaw = inner['maps'];
    if (cid == null || mapsRaw is! List) return;

    final entry = await _entryByCid(cid);
    if (entry == null || entry.type != ChatType.group) return;
    if (!_groupHasMember(entry, senderFp)) {
      DebugHub.instance.log('group_push: отправитель вне группы');
      return;
    }
    if (!entry.trustIncomingSync) return;

    final envelopesRaw = inner['group_key_envelopes'];
    if (envelopesRaw is List) {
      final myEd = await identity.ed25519PublicKey();
      final myFp = ConversationId.fingerprint(myEd);
      for (final e in envelopesRaw) {
        if (e is! Map) continue;
        final env = Map<String, dynamic>.from(e);
        if ((env['recipient_fp'] as String?) != myFp) continue;
        try {
          final key = await ConversationCrypto.unwrapGroupKeyFromEnvelope(
            envelope: env,
            recipientX25519: identity.x25519Static,
            conversationId: cid,
            senderFingerprint: senderFp,
            recipientFingerprint: myFp,
          );
          await store.setGroupMessageKey(cid, key);
          break;
        } catch (_) {}
      }
    }

    ConversationSyncState state;
    try {
      state = await store.loadState(cid);
    } catch (_) {
      return;
    }

    final list = <Map<String, dynamic>>[];
    for (final p in mapsRaw) {
      if (p is Map<String, dynamic>) {
        list.add(p);
      } else if (p is Map) {
        list.add(Map<String, dynamic>.from(p));
      }
    }
    final existing = await store.loadMessagesUnsortedRaw(cid);
    final existingIds = existing.map((e) => ChatMessageRecord.fromJson(e).logicalId).toSet();
    await store.appendInboundRawMaps(state: state, incomingMaps: list);
    final incomingBodies = <String>[];
    for (final m in list) {
      final rec = ChatMessageRecord.fromJson(m);
      if (rec.senderFingerprint == senderFp && !existingIds.contains(rec.logicalId)) {
        incomingBodies.add(rec.body);
      }
    }
    if (incomingBodies.isNotEmpty) {
      final count = incomingBodies.length;
      final body = count == 1 ? incomingBodies.last : 'Новых сообщений: $count';
      await LocalNotifications.instance.showIncomingMessage(
        conversationId: cid,
        title: entry.title,
        body: _notificationPreview(body),
      );
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
}
