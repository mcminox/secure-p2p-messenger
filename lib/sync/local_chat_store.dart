import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../auth/secure_app_repository.dart';
import '../crypto/conversation_crypto.dart';
import '../crypto/public_key_codec.dart';
import '../identity/user_identity.dart';
import 'chat_index.dart';
import 'conversation_id.dart';
import 'models.dart';

class LocalChatStore {
  LocalChatStore({
    this.namespace,
    this.identity,
    this.repository,
  });

  final String? namespace;
  final UserIdentity? identity;
  final SecureAppRepository? repository;

  Future<Directory> _dir() async {
    final root = await getApplicationSupportDirectory();
    final sub = namespace == null ? 'chats' : 'chats_$namespace';
    final d = Directory('${root.path}/$sub');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  Future<Directory> _attachDir() async {
    final d = Directory('${(await _dir()).path}/attachments');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _messagesFile(String conversationId) async {
    final d = await _dir();
    return File('${d.path}/$conversationId.messages.json');
  }

  Future<File> _stateFile(String conversationId) async {
    final d = await _dir();
    return File('${d.path}/$conversationId.state.json');
  }

  Future<File> _indexFile() async {
    final d = await _dir();
    return File('${d.path}/chat_index.json');
  }

  Future<File> _groupKeysFile() async {
    final d = await _dir();
    return File('${d.path}/group_keys.v1.json');
  }

  final _queues = <String, Future<void>>{};

  Future<T> _serialized<T>(String conversationId, Future<T> Function() fn) {
    final prev = _queues[conversationId] ?? Future.value();
    final done = prev.then((_) => fn());
    _queues[conversationId] = done.then((_) {});
    return done;
  }

  Future<ChatListEntry?> _entryFor(String conversationId) async {
    final all = await loadChatEntries();
    try {
      return all.firstWhere((e) => e.conversationId == conversationId);
    } catch (_) {
      return null;
    }
  }

  Future<SecretKey?> _messageKeyFor(String conversationId) async {
    final entry = await _entryFor(conversationId);
    if (entry == null || identity == null) return null;
    if (entry.type == ChatType.direct) {
      final peerX = parseX25519PublicKeyHex(entry.peerX25519PublicHex ?? '');
      if (peerX != null) {
        return ConversationCrypto.directSharedMessageKey(
          myX25519: identity!.x25519Static,
          peerX25519Public: peerX,
          conversationId: conversationId,
        );
      }
      final wrap = repository?.sessionMessageWrapKey;
      if (wrap != null) {
        final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
        return hkdf.deriveKey(
          secretKey: wrap,
          nonce: Uint8List(0),
          info: Uint8List.fromList(utf8.encode('local-wrap|$conversationId')),
        );
      }
    }
    if (entry.type == ChatType.group) {
      return getGroupMessageKey(conversationId);
    }
    return null;
  }

  Future<Map<String, String>> _loadGroupKeyMap() async {
    final f = await _groupKeysFile();
    if (!await f.exists()) return {};
    final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return raw.map((k, v) => MapEntry(k, v as String));
  }

  Future<void> _saveGroupKeyMap(Map<String, String> m) async {
    final f = await _groupKeysFile();
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(m));
  }

  Future<SecretKey?> getGroupMessageKey(String conversationId) async {
    final wrap = repository?.sessionMessageWrapKey;
    if (wrap == null) return null;
    final map = await _loadGroupKeyMap();
    final payload = map[conversationId];
    if (payload == null || payload.isEmpty) return null;
    final env = jsonDecode(payload) as Map<String, dynamic>;
    final key = await ConversationCrypto.openMessageBody(key: wrap, j: env);
    final keyBytes = base64Decode(key);
    return SecretKey(keyBytes);
  }

  Future<void> setGroupMessageKey(String conversationId, SecretKey key) async {
    final wrap = repository?.sessionMessageWrapKey;
    if (wrap == null) {
      throw StateError('Нужна активная разблокированная сессия для установки ключа группы.');
    }
    final map = await _loadGroupKeyMap();
    final keyBytes = await key.extractBytes();
    final sealed = await ConversationCrypto.sealMessageBody(
      key: wrap,
      plaintext: base64Encode(keyBytes),
    );
    map[conversationId] = jsonEncode(sealed);
    await _saveGroupKeyMap(map);
  }

  Future<ChatMessageRecord> _hydrateRecord(Map<String, dynamic> j, String conversationId) async {
    final base = ChatMessageRecord.fromJson(j);
    if (!base.encV1) return base;
    final key = await _messageKeyFor(conversationId);
    if (key == null) return base.withBody('🔒 Нет ключа (разблокируйте или добавьте X25519 контакта)');
    try {
      final plain = await ConversationCrypto.openMessageBody(key: key, j: j);
      return base.withBody(plain);
    } catch (_) {
      return base.withBody('🔒 Ошибка расшифровки');
    }
  }

  Future<Map<String, dynamic>> _sealRecord(ChatMessageRecord r, String conversationId) async {
    final key = await _messageKeyFor(conversationId);
    if (key == null) {
      final entry = await _entryFor(conversationId);
      if (entry?.type == ChatType.direct) {
        throw StateError(
          'Нет X25519-ключа собеседника. Отправка/сохранение в открытом виде запрещены.',
        );
      }
      if (entry?.type == ChatType.group) {
        throw StateError(
          'Нет группового ключа. Откройте защищённую группу заново или дождитесь key-envelope.',
        );
      }
      return r.toJson();
    }
    final sealed = await ConversationCrypto.sealMessageBody(key: key, plaintext: r.body);
    return r.toJsonSealed(sealed);
  }

  Future<List<ChatListEntry>> loadChatEntries() async {
    final f = await _indexFile();
    if (!await f.exists()) return [];
    final raw = jsonDecode(await f.readAsString());
    final list = raw as List<dynamic>;
    return list.map((e) => ChatListEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveChatEntries(List<ChatListEntry> entries) async {
    final f = await _indexFile();
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _upsertEntry(ChatListEntry entry) async {
    final all = await loadChatEntries();
    final i = all.indexWhere((e) => e.conversationId == entry.conversationId);
    final normalizedEntry = entry.type == ChatType.group
        ? entry.copyWith(trustIncomingSync: true)
        : entry;
    if (i >= 0) {
      final prev = all[i];
      all[i] = ChatListEntry(
        conversationId: normalizedEntry.conversationId,
        title: normalizedEntry.title,
        type: normalizedEntry.type,
        updatedAtMillis: normalizedEntry.updatedAtMillis,
        createdAtMillis: prev.createdAtMillis,
        peerPublicKeyHex: normalizedEntry.peerPublicKeyHex ?? prev.peerPublicKeyHex,
        peerX25519PublicHex: normalizedEntry.peerX25519PublicHex ?? prev.peerX25519PublicHex,
        members: normalizedEntry.members ?? prev.members,
        lastPreview: normalizedEntry.lastPreview ?? prev.lastPreview,
        trustIncomingSync: normalizedEntry.type == ChatType.group
            ? true
            : (i >= 0 ? prev.trustIncomingSync : normalizedEntry.trustIncomingSync),
        userPinnedHidden: normalizedEntry.userPinnedHidden || prev.userPinnedHidden,
        hiddenAtMillis: normalizedEntry.hiddenAtMillis ?? prev.hiddenAtMillis,
      );
    } else {
      all.add(normalizedEntry);
    }
    await saveChatEntries(all);
  }

  Future<void> updateChatEntry(ChatListEntry entry) async {
    final all = await loadChatEntries();
    final i = all.indexWhere((e) => e.conversationId == entry.conversationId);
    if (i < 0) return;
    final prev = all[i];
    all[i] = entry.type == ChatType.group ? entry.copyWith(trustIncomingSync: true) : entry;
    await saveChatEntries(all);
    if (_mustRotateGroupKey(prev: prev, next: all[i])) {
      await setGroupMessageKey(all[i].conversationId, ConversationCrypto.randomGroupMessageKey());
    }
  }

  Future<int> enforceDailyDirectResetAndGroupAutoTrust() async {
    final myPub = await identity?.ed25519PublicKey();
    if (myPub == null) return 0;
    final myFp = ConversationId.fingerprint(myPub);
    final all = await loadChatEntries();
    var changedConversations = 0;
    var entriesChanged = false;

    for (var i = 0; i < all.length; i++) {
      final e = all[i];
      if (e.type == ChatType.group) {
        if (!e.trustIncomingSync) {
          all[i] = e.copyWith(trustIncomingSync: true);
          entriesChanged = true;
        }
        continue;
      }
      if (e.trustIncomingSync) {
        all[i] = e.copyWith(trustIncomingSync: false);
        entriesChanged = true;
      }
      final cid = e.conversationId;
      final raw = await loadMessagesUnsortedRaw(cid);
      if (raw.isEmpty) continue;
      final kept = <Map<String, dynamic>>[];
      for (final m in raw) {
        final rec = ChatMessageRecord.fromJson(m);
        if (rec.senderFingerprint == myFp) {
          kept.add(m);
        }
      }
      if (kept.length == raw.length) continue;
      kept.sort((a, b) => _compareRecords(ChatMessageRecord.fromJson(a), ChatMessageRecord.fromJson(b)));
      final mf = await _messagesFile(cid);
      await mf.writeAsString(const JsonEncoder.withIndent('  ').convert(kept));
      changedConversations++;

      try {
        final s = await loadState(cid);
        var myMaxSeq = 0;
        var lamport = 0;
        for (final m in kept) {
          final rec = ChatMessageRecord.fromJson(m);
          if (rec.senderFingerprint == myFp && rec.outboundSeq > myMaxSeq) {
            myMaxSeq = rec.outboundSeq;
          }
          if (rec.lamport > lamport) lamport = rec.lamport;
        }
        final next = ConversationSyncState(
          conversationId: s.conversationId,
          lamportClock: lamport,
          myOutboundSeq: myMaxSeq,
          peerFingerprint: s.peerFingerprint,
          lastRemoteOutboundSeqSeen: 0,
          kind: s.kind,
          groupSeqSeen: s.groupSeqSeen,
        );
        await _saveState(next);
      } catch (_) {}
    }

    await _garbageCollectUnreferencedAttachments();

    if (entriesChanged) {
      await saveChatEntries(all);
    }
    return changedConversations;
  }

  String? _attachmentShaFromMessageMap(Map<String, dynamic> m) {
    final rec = ChatMessageRecord.fromJson(m);
    if (rec.encV1) return null;
    final body = rec.body.trimLeft();
    if (!body.startsWith('{')) return null;
    try {
      final j = jsonDecode(rec.body) as Map<String, dynamic>;
      if (j['k'] != 'att') return null;
      final sha = j['sha256'] as String?;
      if (sha == null || sha.isEmpty) return null;
      return sha;
    } catch (_) {
      return null;
    }
  }

  Future<void> _garbageCollectUnreferencedAttachments() async {
    final used = <String>{};
    final entries = await loadChatEntries();
    for (final e in entries) {
      final raw = await loadMessagesUnsortedRaw(e.conversationId);
      for (final m in raw) {
        final sha = _attachmentShaFromMessageMap(m);
        if (sha != null) used.add(sha);
      }
    }
    final dir = await _attachDir();
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.isEmpty ? '' : e.uri.pathSegments.last;
      if (!name.endsWith('.bin')) continue;
      final sha = name.substring(0, name.length - 4);
      if (used.contains(sha)) continue;
      try {
        await e.delete();
      } catch (_) {}
    }
  }

  bool _mustRotateGroupKey({
    required ChatListEntry prev,
    required ChatListEntry next,
  }) {
    if (prev.type != ChatType.group || next.type != ChatType.group) return false;
    return _groupMembersDigest(prev.members) != _groupMembersDigest(next.members);
  }

  String _groupMembersDigest(List<GroupMemberEntry>? members) {
    final items = <String>[];
    for (final m in members ?? const <GroupMemberEntry>[]) {
      final ed = m.publicKeyHex.trim().replaceAll(RegExp(r'\s'), '').toLowerCase();
      final x = (m.x25519PublicKeyHex ?? '')
          .trim()
          .replaceAll(RegExp(r'\s'), '')
          .toLowerCase();
      items.add('$ed|$x');
    }
    items.sort();
    return items.join(',');
  }

  Future<void> updateEntryPreview(String conversationId, String preview) async {
    final all = await loadChatEntries();
    final i = all.indexWhere((e) => e.conversationId == conversationId);
    if (i < 0) return;
    final e = all[i];
    all[i] = e.copyWith(
      lastPreview: preview,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await saveChatEntries(all);
  }

  Future<ConversationSyncState> loadState(String conversationId) async {
    final f = await _stateFile(conversationId);
    if (!await f.exists()) {
      throw StateError('No sync state — open conversation first.');
    }
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return ConversationSyncState.fromJson(j);
  }

  Future<void> _saveState(ConversationSyncState s) async {
    final f = await _stateFile(s.conversationId);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(s.toJson()));
  }

  Future<List<ChatMessageRecord>> loadMessages(String conversationId) async {
    return _serialized(conversationId, () async {
      final f = await _messagesFile(conversationId);
      if (!await f.exists()) return [];
      final raw = jsonDecode(await f.readAsString());
      final list = raw as List<dynamic>;
      final out = <ChatMessageRecord>[];
      for (final e in list) {
        out.add(await _hydrateRecord(e as Map<String, dynamic>, conversationId));
      }
      out.sort(_compareRecords);
      return out;
    });
  }

  static int _compareRecords(ChatMessageRecord a, ChatMessageRecord b) {
    final c = a.lamport.compareTo(b.lamport);
    if (c != 0) return c;
    final d = a.senderFingerprint.compareTo(b.senderFingerprint);
    if (d != 0) return d;
    return a.outboundSeq.compareTo(b.outboundSeq);
  }

  Future<ConversationSyncState> openConversation({
    required SimplePublicKey myEd25519,
    required SimplePublicKey peerEd25519,
    String? displayTitle,
    String? peerPublicKeyHex,
    String? peerX25519PublicHex,
    bool trustIncomingSync = false,
  }) async {
    final convId = await ConversationId.fromEd25519PublicKeys(myEd25519, peerEd25519);
    final fp = fingerprintsForConversation(myEd25519: myEd25519, peerEd25519: peerEd25519);
    return _serialized(convId, () async {
      final stateFile = await _stateFile(convId);
      ConversationSyncState state;
      if (await stateFile.exists()) {
        final j = jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        state = ConversationSyncState.fromJson(j);
      } else {
        state = ConversationSyncState(
          conversationId: convId,
          lamportClock: 0,
          myOutboundSeq: 0,
          peerFingerprint: fp.$2,
          lastRemoteOutboundSeqSeen: 0,
          kind: ConversationKind.direct,
        );
        await _saveState(state);
        final mf = await _messagesFile(convId);
        await mf.writeAsString('[]');
      }
      if (displayTitle != null && peerPublicKeyHex != null) {
        await _upsertEntry(
          ChatListEntry(
            conversationId: convId,
            title: displayTitle,
            type: ChatType.direct,
            updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
            peerPublicKeyHex: peerPublicKeyHex,
            peerX25519PublicHex: peerX25519PublicHex,
            trustIncomingSync: trustIncomingSync,
          ),
        );
      }
      return state;
    });
  }

  Future<ConversationSyncState> openGroupConversation({
    required String title,
    required List<GroupMemberEntry> members,
    bool trustIncomingSync = false,
  }) async {
    final convId = 'group_${const Uuid().v4()}';
    return _serialized(convId, () async {
      final stateFile = await _stateFile(convId);
      if (await stateFile.exists()) {
        final j = jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        return ConversationSyncState.fromJson(j);
      }
      final initial = ConversationSyncState(
        conversationId: convId,
        lamportClock: 0,
        myOutboundSeq: 0,
        peerFingerprint: '',
        lastRemoteOutboundSeqSeen: 0,
        kind: ConversationKind.group,
        groupSeqSeen: {},
      );
      await _saveState(initial);
      await setGroupMessageKey(convId, ConversationCrypto.randomGroupMessageKey());
      final mf = await _messagesFile(convId);
      await mf.writeAsString('[]');
      await _upsertEntry(
        ChatListEntry(
          conversationId: convId,
          title: title,
          type: ChatType.group,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
          members: members,
          trustIncomingSync: trustIncomingSync,
        ),
      );
      return initial;
    });
  }

  Future<(ChatMessageRecord record, ConversationSyncState newState, Map<String, dynamic> storedMap)> appendOutbound({
    required ConversationSyncState state,
    required String myFingerprint,
    required String body,
  }) async {
    return _serialized(state.conversationId, () async {
      var s = state;
      final lamportClock = s.lamportClock + 1;
      final seq = s.myOutboundSeq + 1;
      final record = ChatMessageRecord(
        conversationId: s.conversationId,
        senderFingerprint: myFingerprint,
        outboundSeq: seq,
        lamport: lamportClock,
        utcMillis: DateTime.now().millisecondsSinceEpoch,
        body: body,
      );
      s = ConversationSyncState(
        conversationId: s.conversationId,
        lamportClock: lamportClock,
        myOutboundSeq: seq,
        peerFingerprint: s.peerFingerprint,
        lastRemoteOutboundSeqSeen: s.lastRemoteOutboundSeqSeen,
        kind: s.kind,
        groupSeqSeen: s.groupSeqSeen,
      );
      final stored = await _sealRecord(record, s.conversationId);
      await _appendMaps(s.conversationId, [stored]);
      await _saveState(s);
      return (record, s, stored);
    });
  }

  Future<ConversationSyncState> appendInbound({
    required ConversationSyncState state,
    required List<ChatMessageRecord> incoming,
  }) async {
    if (incoming.isEmpty) return state;
    return _serialized(state.conversationId, () async {
      for (final m in incoming) {
        if (m.conversationId != state.conversationId) {
          throw ArgumentError('Conversation mismatch');
        }
      }
      final sorted = [...incoming]..sort(_compareRecords);
      var clock = state.lamportClock;
      for (final m in sorted) {
        final mx = clock > m.lamport ? clock : m.lamport;
        clock = mx + 1;
      }

      if (state.kind == ConversationKind.group) {
        final map = Map<String, int>.from(state.groupSeqSeen ?? {});
        for (final m in incoming) {
          final prev = map[m.senderFingerprint] ?? 0;
          if (m.outboundSeq > prev) map[m.senderFingerprint] = m.outboundSeq;
        }
        final next = ConversationSyncState(
          conversationId: state.conversationId,
          lamportClock: clock,
          myOutboundSeq: state.myOutboundSeq,
          peerFingerprint: state.peerFingerprint,
          lastRemoteOutboundSeqSeen: state.lastRemoteOutboundSeqSeen,
          kind: ConversationKind.group,
          groupSeqSeen: map,
        );
        final maps = <Map<String, dynamic>>[];
        for (final m in incoming) {
          maps.add(await _sealRecord(m, state.conversationId));
        }
        await _appendMaps(state.conversationId, maps);
        await _saveState(next);
        return next;
      }

      var maxPeer = state.lastRemoteOutboundSeqSeen;
      for (final m in incoming) {
        if (m.senderFingerprint == state.peerFingerprint && m.outboundSeq > maxPeer) {
          maxPeer = m.outboundSeq;
        }
      }
      final next = ConversationSyncState(
        conversationId: state.conversationId,
        lamportClock: clock,
        myOutboundSeq: state.myOutboundSeq,
        peerFingerprint: state.peerFingerprint,
        lastRemoteOutboundSeqSeen: maxPeer,
        kind: state.kind,
        groupSeqSeen: state.groupSeqSeen,
      );
      final maps = <Map<String, dynamic>>[];
      for (final m in incoming) {
        maps.add(await _sealRecord(m, state.conversationId));
      }
      await _appendMaps(state.conversationId, maps);
      await _saveState(next);
      return next;
    });
  }

  Future<void> _appendMaps(String conversationId, List<Map<String, dynamic>> batch) async {
    final existing = await loadMessagesUnsortedRaw(conversationId);
    final byId = <String, Map<String, dynamic>>{};
    for (final m in existing) {
      final r = ChatMessageRecord.fromJson(m);
      byId[r.logicalId] = m;
    }
    for (final m in batch) {
      final r = ChatMessageRecord.fromJson(m);
      byId[r.logicalId] = m;
    }
    final merged = byId.values.toList();
    merged.sort((a, b) {
      final x = ChatMessageRecord.fromJson(a);
      final y = ChatMessageRecord.fromJson(b);
      return _compareRecords(x, y);
    });
    final f = await _messagesFile(conversationId);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(merged));
  }

  Future<List<Map<String, dynamic>>> loadMessagesUnsortedRaw(String conversationId) async {
    final f = await _messagesFile(conversationId);
    if (!await f.exists()) return [];
    final raw = jsonDecode(await f.readAsString());
    final list = raw as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<List<ChatMessageRecord>> loadMessagesUnsorted(String conversationId) async {
    final raw = await loadMessagesUnsortedRaw(conversationId);
    final out = <ChatMessageRecord>[];
    for (final m in raw) {
      out.add(await _hydrateRecord(m, conversationId));
    }
    return out;
  }

  Future<List<ChatMessageRecord>> sliceOutboundFromAuthor({
    required String conversationId,
    required String authorFingerprint,
    required int afterSeq,
    required int maxMessages,
  }) async {
    final all = await loadMessages(conversationId);
    return all
        .where((m) => m.senderFingerprint == authorFingerprint && m.outboundSeq > afterSeq)
        .take(maxMessages)
        .toList();
  }

  Future<List<Map<String, dynamic>>> sliceOutboundMapsFromAuthor({
    required String conversationId,
    required String authorFingerprint,
    required int afterSeq,
    required int maxMessages,
  }) async {
    final raw = await loadMessagesUnsortedRaw(conversationId);
    final filtered = raw.where((j) {
      final m = ChatMessageRecord.fromJson(j);
      return m.senderFingerprint == authorFingerprint && m.outboundSeq > afterSeq;
    }).toList();
    filtered.sort((a, b) => _compareRecords(ChatMessageRecord.fromJson(a), ChatMessageRecord.fromJson(b)));
    return filtered.take(maxMessages).toList();
  }

  Future<ConversationSyncState> appendInboundRawMaps({
    required ConversationSyncState state,
    required List<Map<String, dynamic>> incomingMaps,
  }) async {
    if (incomingMaps.isEmpty) return state;
    return _serialized(state.conversationId, () async {
      final incoming = incomingMaps.map(ChatMessageRecord.fromJson).toList();
      for (final m in incoming) {
        if (m.conversationId != state.conversationId) {
          throw ArgumentError('Conversation mismatch');
        }
      }
      final sorted = [...incoming]..sort(_compareRecords);
      var clock = state.lamportClock;
      for (final m in sorted) {
        final mx = clock > m.lamport ? clock : m.lamport;
        clock = mx + 1;
      }

      if (state.kind == ConversationKind.group) {
        final map = Map<String, int>.from(state.groupSeqSeen ?? {});
        for (final m in incoming) {
          final prev = map[m.senderFingerprint] ?? 0;
          if (m.outboundSeq > prev) map[m.senderFingerprint] = m.outboundSeq;
        }
        final next = ConversationSyncState(
          conversationId: state.conversationId,
          lamportClock: clock,
          myOutboundSeq: state.myOutboundSeq,
          peerFingerprint: state.peerFingerprint,
          lastRemoteOutboundSeqSeen: state.lastRemoteOutboundSeqSeen,
          kind: ConversationKind.group,
          groupSeqSeen: map,
        );
        await _appendMaps(state.conversationId, incomingMaps);
        await _saveState(next);
        return next;
      }

      var maxPeer = state.lastRemoteOutboundSeqSeen;
      for (final m in incoming) {
        if (m.senderFingerprint == state.peerFingerprint && m.outboundSeq > maxPeer) {
          maxPeer = m.outboundSeq;
        }
      }
      final next = ConversationSyncState(
        conversationId: state.conversationId,
        lamportClock: clock,
        myOutboundSeq: state.myOutboundSeq,
        peerFingerprint: state.peerFingerprint,
        lastRemoteOutboundSeqSeen: maxPeer,
        kind: state.kind,
        groupSeqSeen: state.groupSeqSeen,
      );
      await _appendMaps(state.conversationId, incomingMaps);
      await _saveState(next);
      return next;
    });
  }

  Future<void> deleteConversation(String conversationId) async {
    final mf = await _messagesFile(conversationId);
    final sf = await _stateFile(conversationId);
    try {
      if (await mf.exists()) await mf.delete();
    } catch (_) {}
    try {
      if (await sf.exists()) await sf.delete();
    } catch (_) {}
    final all = await loadChatEntries();
    all.removeWhere((e) => e.conversationId == conversationId);
    await saveChatEntries(all);
    final gm = await _loadGroupKeyMap();
    if (gm.remove(conversationId) != null) {
      await _saveGroupKeyMap(gm);
    }
  }

  Future<File> attachmentFile(String sha256Hex) async {
    final d = await _attachDir();
    return File('${d.path}/$sha256Hex.bin');
  }
}
