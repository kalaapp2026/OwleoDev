/// One compose action of the Messages module. `audienceType` stays a plain wire string, matching
/// how Events models its own identical field.
class Broadcast {
  final String id;
  final String title;
  final String body;
  final String audienceType;
  final Set<String> courseIds;
  final Set<String> batchIds;
  final Set<String> individualIds;
  final int recipientCount;
  final String createdAt;

  Broadcast({
    required this.id,
    required this.title,
    required this.body,
    required this.audienceType,
    required this.courseIds,
    required this.batchIds,
    required this.individualIds,
    required this.recipientCount,
    required this.createdAt,
  });

  factory Broadcast.fromJson(Map<String, dynamic> json) => Broadcast(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        audienceType: json['audienceType'] as String? ?? 'ALL_STUDENTS',
        courseIds: Set<String>.from(json['courseIds'] as List? ?? const []),
        batchIds: Set<String>.from(json['batchIds'] as List? ?? const []),
        individualIds: Set<String>.from(json['individualIds'] as List? ?? const []),
        recipientCount: json['recipientCount'] as int? ?? 0,
        createdAt: json['createdAt'] as String? ?? '',
      );
}
