class Event {
  final String id;
  final String academyId;
  final String type;
  final String title;
  final String? description;
  final String eventDate;
  final String? location;
  final String visibility;
  final String? coverImageUrl;

  const Event({
    required this.id,
    required this.academyId,
    required this.type,
    required this.title,
    required this.description,
    required this.eventDate,
    required this.location,
    required this.visibility,
    required this.coverImageUrl,
  });

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        id: json['id'] as String,
        academyId: json['academyId'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        eventDate: json['eventDate'] as String,
        location: json['location'] as String?,
        visibility: json['visibility'] as String,
        coverImageUrl: json['coverImageUrl'] as String?,
      );
}
