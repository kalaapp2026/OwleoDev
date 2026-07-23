/// What kind of file a material attachment is - lets the UI show an image thumbnail vs a PDF
/// icon+open link without having to sniff the URL itself.
enum ReferenceMaterialType { none, image, pdf }

ReferenceMaterialType referenceMaterialTypeFromString(String? value) => switch (value) {
      'IMAGE' => ReferenceMaterialType.image,
      'PDF' => ReferenceMaterialType.pdf,
      _ => ReferenceMaterialType.none,
    };

class SyllabusUnit {
  final String id;
  final String courseId;
  final Set<String> batchIds;
  final String title;
  final String? description;
  final int orderIndex;
  final String status;

  const SyllabusUnit({
    required this.id,
    required this.courseId,
    required this.batchIds,
    required this.title,
    required this.description,
    required this.orderIndex,
    required this.status,
  });

  /// Empty batchIds means this material applies to the whole course - anyone enrolled sees it.
  bool get isCourseWide => batchIds.isEmpty;

  factory SyllabusUnit.fromJson(Map<String, dynamic> json) => SyllabusUnit(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        batchIds: Set<String>.from(json['batchIds'] as List? ?? const []),
        title: json['title'] as String,
        description: json['description'] as String?,
        orderIndex: json['orderIndex'] as int,
        status: json['status'] as String,
      );
}

/// A PDF/image attachment on a SyllabusUnit - a unit can have several of these (a worksheet plus
/// a diagram, several scanned pages, etc.), fetched/managed as their own small list.
class MaterialAttachment {
  final String id;
  final String syllabusUnitId;
  final String url;
  final ReferenceMaterialType materialType;
  final String? contentType;

  const MaterialAttachment({
    required this.id,
    required this.syllabusUnitId,
    required this.url,
    required this.materialType,
    required this.contentType,
  });

  factory MaterialAttachment.fromJson(Map<String, dynamic> json) => MaterialAttachment(
        id: json['id'] as String,
        syllabusUnitId: json['syllabusUnitId'] as String,
        url: json['url'] as String,
        materialType: referenceMaterialTypeFromString(json['materialType'] as String?),
        contentType: json['contentType'] as String?,
      );
}

/// A song attachment on a SyllabusUnit - streamOnly is the whole "play in-app only, or actually
/// downloadable" distinction (the trainer/admin who uploaded it decides).
class Track {
  final String id;
  final String syllabusUnitId;
  final String title;
  final String url;
  final String? contentType;
  final bool streamOnly;

  const Track({
    required this.id,
    required this.syllabusUnitId,
    required this.title,
    required this.url,
    required this.contentType,
    required this.streamOnly,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        syllabusUnitId: json['syllabusUnitId'] as String,
        title: json['title'] as String,
        url: json['url'] as String,
        contentType: json['contentType'] as String?,
        streamOnly: json['streamOnly'] as bool? ?? true,
      );
}
