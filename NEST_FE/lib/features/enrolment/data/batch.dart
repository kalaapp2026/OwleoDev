class Batch {
  final String id;
  final String courseId;
  final String name;
  final String? description;
  final String batchType;
  final String? trainerMembershipId;
  final String? trainerName;
  final String status;

  const Batch({
    required this.id,
    required this.courseId,
    required this.name,
    required this.description,
    required this.batchType,
    required this.trainerMembershipId,
    required this.trainerName,
    required this.status,
  });

  factory Batch.fromJson(Map<String, dynamic> json) => Batch(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        batchType: json['batchType'] as String,
        trainerMembershipId: json['trainerMembershipId'] as String?,
        trainerName: json['trainerName'] as String?,
        status: json['status'] as String,
      );
}
