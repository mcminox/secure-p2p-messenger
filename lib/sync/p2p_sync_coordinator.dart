import 'local_chat_store.dart';
import 'models.dart';
import 'sync_wire.dart';

class P2pSyncCoordinator {
  P2pSyncCoordinator(this.store);

  final LocalChatStore store;

  Map<String, dynamic> buildPullRequest({
    required ConversationSyncState state,
    required String requesterFingerprint,
  }) {
    return SyncWire.pullRequest(
      conversationId: state.conversationId,
      requesterFingerprint: requesterFingerprint,
      afterRemoteOutboundSeqExclusive: state.lastRemoteOutboundSeqSeen,
    );
  }

  Future<List<Map<String, dynamic>>> responderHandlePullRequest({
    required ConversationSyncState responderState,
    required String responderFingerprint,
    required Map<String, dynamic> request,
    required bool allow,
    String? denyReason,
    int maxMessages = 200,
  }) async {
    final conv = request['conversation_id'] as String;
    if (conv != responderState.conversationId) {
      throw ArgumentError('conversation_id mismatch');
    }
    final after = (request['after_remote_outbound_seq_exclusive'] as num).toInt();
    if (!allow) {
      return [
        SyncWire.pullGrant(
          conversationId: responderState.conversationId,
          allowed: false,
          afterRemoteOutboundSeqExclusive: after,
          maxMessages: maxMessages,
          reason: denyReason ?? 'Пользователь запретил подгрузку',
        ),
      ];
    }
    final batch = await store.sliceOutboundMapsFromAuthor(
      conversationId: responderState.conversationId,
      authorFingerprint: responderFingerprint,
      afterSeq: after,
      maxMessages: maxMessages,
    );
    return [
      SyncWire.pullGrant(
        conversationId: responderState.conversationId,
        allowed: true,
        afterRemoteOutboundSeqExclusive: after,
        maxMessages: maxMessages,
      ),
      SyncWire.messageBatch(
        conversationId: responderState.conversationId,
        messageMaps: batch,
      ),
    ];
  }

  Future<ConversationSyncState> requesterApplyPackets({
    required ConversationSyncState state,
    required List<Map<String, dynamic>> packets,
  }) async {
    var s = state;
    for (final p in packets) {
      final type = p['type'] as String?;
      if (type == SyncWire.typeMessageBatch) {
        final raw = p['messages'] as List<dynamic>;
        final list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        s = await store.appendInboundRawMaps(state: s, incomingMaps: list);
      }
    }
    return s;
  }

  static bool isPullDenied(Map<String, dynamic> packet) {
    final t = packet['type'] as String?;
    if (t == SyncWire.typePullDeny) return true;
    if (t == SyncWire.typePullGrant && packet['allowed'] == false) return true;
    return false;
  }

  static bool isPullAllowed(Map<String, dynamic> packet) {
    return packet['type'] == SyncWire.typePullGrant && packet['allowed'] == true;
  }
}
