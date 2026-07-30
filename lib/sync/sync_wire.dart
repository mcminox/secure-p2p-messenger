abstract class SyncWire {
  static const v1 = 1;

  static const typeHello = 'sync_hello';
  static const typePullRequest = 'sync_pull_request';
  static const typePullGrant = 'sync_pull_grant';
  static const typePullDeny = 'sync_pull_deny';
  static const typeMessageBatch = 'sync_message_batch';

  static Map<String, dynamic> hello({
    required String conversationId,
    required String fingerprint,
    required int lastRemoteOutboundSeqSeen,
    required int myMaxOutboundSeq,
    required int lamportClock,
  }) =>
      {
        'v': v1,
        'type': typeHello,
        'conversation_id': conversationId,
        'fingerprint': fingerprint,
        'last_remote_outbound_seq_seen': lastRemoteOutboundSeqSeen,
        'my_max_outbound_seq': myMaxOutboundSeq,
        'lamport_clock': lamportClock,
      };

  static Map<String, dynamic> pullRequest({
    required String conversationId,
    required String requesterFingerprint,
    required int afterRemoteOutboundSeqExclusive,
  }) =>
      {
        'v': v1,
        'type': typePullRequest,
        'conversation_id': conversationId,
        'requester_fingerprint': requesterFingerprint,
        'after_remote_outbound_seq_exclusive': afterRemoteOutboundSeqExclusive,
      };

  static Map<String, dynamic> pullGrant({
    required String conversationId,
    required bool allowed,
    required int afterRemoteOutboundSeqExclusive,
    int maxMessages = 200,
    String? reason,
  }) =>
      {
        'v': v1,
        'type': allowed ? typePullGrant : typePullDeny,
        'conversation_id': conversationId,
        'allowed': allowed,
        'after_remote_outbound_seq_exclusive': afterRemoteOutboundSeqExclusive,
        'max_messages': maxMessages,
        if (reason != null) 'reason': reason,
      };

  static Map<String, dynamic> messageBatch({
    required String conversationId,
    required List<Map<String, dynamic>> messageMaps,
  }) =>
      {
        'v': v1,
        'type': typeMessageBatch,
        'conversation_id': conversationId,
        'messages': messageMaps,
      };
}
