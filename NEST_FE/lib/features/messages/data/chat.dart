/// Someone the caller can chat with. [subtitle] is their courses, or their role when they have none.
class ChatContact {
  final String membershipId;
  final String name;
  final String roleType;
  final String subtitle;

  const ChatContact({required this.membershipId, required this.name, required this.roleType, required this.subtitle});

  bool get isTrainer => roleType == 'TRAINER';
  bool get isAdmin => roleType == 'ACADEMY_ADMIN';

  factory ChatContact.fromJson(Map<String, dynamic> json) => ChatContact(
        membershipId: json['membershipId'] as String,
        name: json['name'] as String? ?? '',
        roleType: json['roleType'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
      );
}

/// One row of the chat list.
class Conversation {
  final String id;
  final ChatContact contact;
  final String? lastMessage;
  final bool lastMessageFromMe;
  final String lastMessageAt;
  final int unreadCount;

  const Conversation({
    required this.id,
    required this.contact,
    required this.lastMessage,
    required this.lastMessageFromMe,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        contact: ChatContact.fromJson(json['contact'] as Map<String, dynamic>),
        lastMessage: json['lastMessage'] as String?,
        lastMessageFromMe: json['lastMessageFromMe'] as bool? ?? false,
        lastMessageAt: json['lastMessageAt'] as String? ?? '',
        unreadCount: json['unreadCount'] as int? ?? 0,
      );
}

class ChatMessage {
  final String id;
  final bool fromMe;
  final String body;
  final String createdAt;

  const ChatMessage({required this.id, required this.fromMe, required this.body, required this.createdAt});

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        fromMe: json['fromMe'] as bool? ?? false,
        body: json['body'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
      );
}
