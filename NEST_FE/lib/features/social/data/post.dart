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

  /// Resolved server-side: the Academy's name/logo for a membership-authored post (Admin/Trainer -
  /// PRD 3.12's "posted from the Academy's verified profile"), or the person's own name/photo for
  /// an Artist/Super Admin's personal post.
  final String? authorDisplayName;
  final String? authorAvatarUrl;

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
    required this.authorDisplayName,
    required this.authorAvatarUrl,
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
        authorDisplayName: json['authorDisplayName'] as String?,
        authorAvatarUrl: json['authorAvatarUrl'] as String?,
      );
}
