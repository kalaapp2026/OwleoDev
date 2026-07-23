class Post {
  final String id;
  final String? authorMembershipId;
  final String? authorUserId;
  final String type;
  final String? content;
  final List<String> mediaUrls;
  final String visibility;
  final String? eventId;
  final String? createdAt;

  const Post({
    required this.id,
    required this.authorMembershipId,
    required this.authorUserId,
    required this.type,
    required this.content,
    required this.mediaUrls,
    required this.visibility,
    required this.eventId,
    required this.createdAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as String,
        authorMembershipId: json['authorMembershipId'] as String?,
        authorUserId: json['authorUserId'] as String?,
        type: json['type'] as String,
        content: json['content'] as String?,
        mediaUrls: List<String>.from(json['mediaUrls'] as List? ?? []),
        visibility: json['visibility'] as String,
        eventId: json['eventId'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}
