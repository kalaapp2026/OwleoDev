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

  /// How many recipients have opened it; null for a broadcast sent before read tracking existed.
  final int? readCount;

  /// Who it went to in words - "All students", the course names, the batch names.
  final String? audienceLabel;

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
    this.readCount,
    this.audienceLabel,
  });

  factory Broadcast.fromJson(Map<String, dynamic> json) => Broadcast(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String,
        audienceType: json['audienceType'] as String? ?? 'ALL_STUDENTS',
        courseIds: Set<String>.from(json['courseIds'] as List? ?? const []),
        batchIds: Set<String>.from(json['batchIds'] as List? ?? const []),
        individualIds: Set<String>.from(json['individualIds'] as List? ?? const []),
        recipientCount: json['recipientCount'] as int? ?? 0,
        createdAt: json['createdAt'] as String? ?? '',
        readCount: json['readCount'] as int?,
        audienceLabel: json['audienceLabel'] as String?,
      );
}

/// One person a broadcast reached, and whether they have opened it.
class BroadcastRecipient {
  final String membershipId;
  final String name;
  final String roleType;
  final bool read;

  const BroadcastRecipient({required this.membershipId, required this.name, required this.roleType, required this.read});

  bool get isTrainer => roleType == 'TRAINER';

  factory BroadcastRecipient.fromJson(Map<String, dynamic> json) => BroadcastRecipient(
        membershipId: json['membershipId'] as String,
        name: json['name'] as String? ?? '',
        roleType: json['roleType'] as String? ?? '',
        read: json['read'] as bool? ?? false,
      );
}

/// A broadcast plus its per-person list. [recipients] is empty for one sent before read tracking.
class BroadcastDetail {
  final Broadcast broadcast;
  final List<BroadcastRecipient> recipients;

  const BroadcastDetail({required this.broadcast, required this.recipients});

  factory BroadcastDetail.fromJson(Map<String, dynamic> json) => BroadcastDetail(
        broadcast: Broadcast.fromJson(json['broadcast'] as Map<String, dynamic>),
        recipients: (json['recipients'] as List? ?? const [])
            .map((e) => BroadcastRecipient.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
