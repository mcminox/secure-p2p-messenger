import 'package:cryptography/cryptography.dart';

import 'conversation_id.dart';

enum ConversationKind { direct, group }

class ChatMessageRecord {
  ChatMessageRecord({
    required this.conversationId,
    required this.senderFingerprint,
    required this.outboundSeq,
    required this.lamport,
    required this.utcMillis,
    required this.body,
    this.encV1 = false,
  });

  final String conversationId;
  final String senderFingerprint;
  final int outboundSeq;
  final int lamport;
  final int utcMillis;

  final String body;

  final bool encV1;

  String get logicalId => '$senderFingerprint:$outboundSeq';

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        'sender_fingerprint': senderFingerprint,
        'outbound_seq': outboundSeq,
        'lamport': lamport,
        'utc_millis': utcMillis,
        'body': body,
      };

  Map<String, dynamic> toJsonSealed(Map<String, dynamic> sealed) => {
        'conversation_id': conversationId,
        'sender_fingerprint': senderFingerprint,
        'outbound_seq': outboundSeq,
        'lamport': lamport,
        'utc_millis': utcMillis,
        ...sealed,
      };

  factory ChatMessageRecord.fromJson(Map<String, dynamic> j) {
    final enc = j['enc_v1'] == true;
    return ChatMessageRecord(
      conversationId: j['conversation_id'] as String,
      senderFingerprint: j['sender_fingerprint'] as String,
      outboundSeq: (j['outbound_seq'] as num).toInt(),
      lamport: (j['lamport'] as num).toInt(),
      utcMillis: (j['utc_millis'] as num).toInt(),
      body: enc ? '' : (j['body'] as String? ?? ''),
      encV1: enc,
    );
  }

  ChatMessageRecord withBody(String plain) => ChatMessageRecord(
        conversationId: conversationId,
        senderFingerprint: senderFingerprint,
        outboundSeq: outboundSeq,
        lamport: lamport,
        utcMillis: utcMillis,
        body: plain,
        encV1: false,
      );
}

class ConversationSyncState {
  ConversationSyncState({
    required this.conversationId,
    required this.lamportClock,
    required this.myOutboundSeq,
    required this.peerFingerprint,
    required this.lastRemoteOutboundSeqSeen,
    this.kind = ConversationKind.direct,
    this.groupSeqSeen,
  });

  final String conversationId;
  final int lamportClock;
  final int myOutboundSeq;
  final String peerFingerprint;
  final int lastRemoteOutboundSeqSeen;
  final ConversationKind kind;
  final Map<String, int>? groupSeqSeen;

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        'lamport_clock': lamportClock,
        'my_outbound_seq': myOutboundSeq,
        'peer_fingerprint': peerFingerprint,
        'last_remote_outbound_seq_seen': lastRemoteOutboundSeqSeen,
        'kind': kind.name,
        if (groupSeqSeen != null && groupSeqSeen!.isNotEmpty) 'group_seq_seen': groupSeqSeen,
      };

  factory ConversationSyncState.fromJson(Map<String, dynamic> j) {
    final id = j['conversation_id'] as String;
    final kindStr = j['kind'] as String?;
    final kind = switch (kindStr) {
      'group' => ConversationKind.group,
      'direct' => ConversationKind.direct,
      _ => id.startsWith('group_') ? ConversationKind.group : ConversationKind.direct,
    };
    final gsm = j['group_seq_seen'] as Map<String, dynamic>?;
    return ConversationSyncState(
      conversationId: id,
      lamportClock: ((j['lamport_clock'] ?? j['local_lamport']) as num).toInt(),
      myOutboundSeq: (j['my_outbound_seq'] as num).toInt(),
      peerFingerprint: j['peer_fingerprint'] as String? ?? '',
      lastRemoteOutboundSeqSeen: (j['last_remote_outbound_seq_seen'] as num).toInt(),
      kind: kind,
      groupSeqSeen: gsm?.map((k, v) => MapEntry(k, (v as num).toInt())),
    );
  }

  ConversationSyncState copyWith({
    int? lamportClock,
    int? myOutboundSeq,
    int? lastRemoteOutboundSeqSeen,
    Map<String, int>? groupSeqSeen,
  }) =>
      ConversationSyncState(
        conversationId: conversationId,
        lamportClock: lamportClock ?? this.lamportClock,
        myOutboundSeq: myOutboundSeq ?? this.myOutboundSeq,
        peerFingerprint: peerFingerprint,
        lastRemoteOutboundSeqSeen: lastRemoteOutboundSeqSeen ?? this.lastRemoteOutboundSeqSeen,
        kind: kind,
        groupSeqSeen: groupSeqSeen ?? this.groupSeqSeen,
      );
}

(String me, String peer) fingerprintsForConversation({
  required SimplePublicKey myEd25519,
  required SimplePublicKey peerEd25519,
}) {
  return (
    ConversationId.fingerprint(myEd25519),
    ConversationId.fingerprint(peerEd25519),
  );
}
