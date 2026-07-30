
enum ChatType { direct, group }

class GroupMemberEntry {
  GroupMemberEntry({
    required this.displayName,
    required this.publicKeyHex,
    this.x25519PublicKeyHex,
  });

  final String displayName;
  final String publicKeyHex;

  final String? x25519PublicKeyHex;

  Map<String, dynamic> toJson() => {
        'display_name': displayName,
        'public_key_hex': publicKeyHex,
        if (x25519PublicKeyHex != null) 'x25519_public_key_hex': x25519PublicKeyHex,
      };

  factory GroupMemberEntry.fromJson(Map<String, dynamic> j) => GroupMemberEntry(
        displayName: j['display_name'] as String,
        publicKeyHex: j['public_key_hex'] as String,
        x25519PublicKeyHex: j['x25519_public_key_hex'] as String?,
      );
}

class ChatListEntry {
  ChatListEntry({
    required this.conversationId,
    required this.title,
    required this.type,
    required this.updatedAtMillis,
    int? createdAtMillis,
    this.peerPublicKeyHex,
    this.peerX25519PublicHex,
    this.members,
    this.lastPreview,
    this.trustIncomingSync = false,
    this.userPinnedHidden = false,
    this.hiddenAtMillis,
  }) : createdAtMillis = createdAtMillis ?? updatedAtMillis;

  final String conversationId;
  final String title;
  final ChatType type;
  final int updatedAtMillis;
  final int createdAtMillis;

  final String? peerPublicKeyHex;

  final String? peerX25519PublicHex;

  final List<GroupMemberEntry>? members;
  final String? lastPreview;

  final bool trustIncomingSync;

  final bool userPinnedHidden;

  final int? hiddenAtMillis;

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        'title': title,
        'type': type.name,
        'updated_at_millis': updatedAtMillis,
        'created_at_millis': createdAtMillis,
        if (peerPublicKeyHex != null) 'peer_public_key_hex': peerPublicKeyHex,
        if (peerX25519PublicHex != null) 'peer_x25519_public_key_hex': peerX25519PublicHex,
        if (members != null) 'members': members!.map((e) => e.toJson()).toList(),
        if (lastPreview != null) 'last_preview': lastPreview,
        'trust_incoming_sync': trustIncomingSync,
        'user_pinned_hidden': userPinnedHidden,
        if (hiddenAtMillis != null) 'hidden_at_millis': hiddenAtMillis,
      };

  factory ChatListEntry.fromJson(Map<String, dynamic> j) {
    final t = j['type'] as String?;
    final type = ChatType.values.firstWhere(
      (e) => e.name == t,
      orElse: () => ChatType.direct,
    );
    final updated = (j['updated_at_millis'] as num).toInt();
    return ChatListEntry(
      conversationId: j['conversation_id'] as String,
      title: j['title'] as String,
      type: type,
      updatedAtMillis: updated,
      createdAtMillis: (j['created_at_millis'] as num?)?.toInt() ?? updated,
      peerPublicKeyHex: j['peer_public_key_hex'] as String?,
      peerX25519PublicHex: j['peer_x25519_public_key_hex'] as String?,
      members: (j['members'] as List<dynamic>?)
          ?.map((e) => GroupMemberEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastPreview: j['last_preview'] as String?,
      trustIncomingSync: j['trust_incoming_sync'] as bool? ?? false,
      userPinnedHidden: j['user_pinned_hidden'] as bool? ?? false,
      hiddenAtMillis: (j['hidden_at_millis'] as num?)?.toInt(),
    );
  }

  ChatListEntry copyWith({
    String? title,
    int? updatedAtMillis,
    String? lastPreview,
    bool? trustIncomingSync,
    bool? userPinnedHidden,
    int? hiddenAtMillis,
    String? peerX25519PublicHex,
    List<GroupMemberEntry>? members,
    bool clearHiddenAt = false,
  }) =>
      ChatListEntry(
        conversationId: conversationId,
        title: title ?? this.title,
        type: type,
        updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
        createdAtMillis: createdAtMillis,
        peerPublicKeyHex: peerPublicKeyHex,
        peerX25519PublicHex: peerX25519PublicHex ?? this.peerX25519PublicHex,
        members: members ?? this.members,
        lastPreview: lastPreview ?? this.lastPreview,
        trustIncomingSync: trustIncomingSync ?? this.trustIncomingSync,
        userPinnedHidden: userPinnedHidden ?? this.userPinnedHidden,
        hiddenAtMillis: clearHiddenAt ? null : (hiddenAtMillis ?? this.hiddenAtMillis),
      );
}
