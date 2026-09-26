/// Mirrors the backend's EventResponse. Enum-shaped fields (`type`, `visibility`, `status`,
/// `audienceType`) stay plain strings, matching how `type`/`visibility` were already modelled
/// before this rewrite - `events_tab.dart`'s Social-side card already compares `event.type` as a
/// raw string, and changing that would mean touching a screen this module is scoped to leave
/// alone.
class Event {
  final String id;
  final String academyId;
  final String type;
  final String title;
  final String? description;
  final String eventDate;
  final String? endDate;
  final String? location;
  final String? venueMapsUrl;
  final String visibility;
  final String? coverImageUrl;
  final String? interestDeadline;
  final String status;
  final String audienceType;
  final Set<String> courseIds;
  final Set<String> batchIds;
  final Set<String> individualIds;

  /// Real roster-derived count for who `audienceType` targets - see the backend's own doc
  /// comment on why this stays a count rather than a full roster.
  final int invitedCount;

  /// How many people have marked themselves interested (Social's existing, unrestricted
  /// `POST /interests`).
  final int interestedCount;

  const Event({
    required this.id,
    required this.academyId,
    required this.type,
    required this.title,
    required this.description,
    required this.eventDate,
    required this.endDate,
    required this.location,
    required this.venueMapsUrl,
    required this.visibility,
    required this.coverImageUrl,
    required this.interestDeadline,
    required this.status,
    required this.audienceType,
    required this.courseIds,
    required this.batchIds,
    required this.individualIds,
    required this.invitedCount,
    required this.interestedCount,
  });

  bool get isCancelled => status == 'CANCELLED';
  bool get isDraft => status == 'DRAFT';
  bool get isMultiDay {
    if (endDate == null) return false;
    return endDate!.split('T').first != eventDate.split('T').first;
  }

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        id: json['id'] as String,
        academyId: json['academyId'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        eventDate: json['eventDate'] as String,
        endDate: json['endDate'] as String?,
        location: json['location'] as String?,
        venueMapsUrl: json['venueMapsUrl'] as String?,
        visibility: json['visibility'] as String,
        coverImageUrl: json['coverImageUrl'] as String?,
        interestDeadline: json['interestDeadline'] as String?,
        status: json['status'] as String? ?? 'PUBLISHED',
        audienceType: json['audienceType'] as String? ?? 'ALL_STUDENTS',
        courseIds: Set<String>.from(json['courseIds'] as List? ?? const []),
        batchIds: Set<String>.from(json['batchIds'] as List? ?? const []),
        individualIds: Set<String>.from(json['individualIds'] as List? ?? const []),
        invitedCount: json['invitedCount'] as int? ?? 0,
        interestedCount: json['interestedCount'] as int? ?? 0,
      );
}

/// One person who marked interest - the ERP event detail screen's interested-students list.
class InterestedPerson {
  final String userId;
  final String fullName;
  final String? profileImageUrl;

  const InterestedPerson({required this.userId, required this.fullName, required this.profileImageUrl});

  factory InterestedPerson.fromJson(Map<String, dynamic> json) => InterestedPerson(
        userId: json['userId'] as String,
        fullName: json['fullName'] as String,
        profileImageUrl: json['profileImageUrl'] as String?,
      );
}

class EventInterests {
  final int count;
  final List<InterestedPerson> interested;

  const EventInterests({required this.count, required this.interested});

  factory EventInterests.fromJson(Map<String, dynamic> json) => EventInterests(
        count: json['count'] as int? ?? 0,
        interested: (json['interested'] as List? ?? []).map((e) => InterestedPerson.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
