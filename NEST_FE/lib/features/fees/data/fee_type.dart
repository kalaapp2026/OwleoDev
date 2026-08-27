/// Which batch a fee type applies to, with names so the selector needs no second round trip.
class FeeTypeBatchBinding {
  const FeeTypeBatchBinding({
    required this.batchId,
    required this.batchName,
    required this.courseId,
    required this.courseName,
  });

  final String batchId;
  final String batchName;
  final String courseId;
  final String courseName;

  /// How the prototype labels a batch in the Other Fees selector: "Guitar Beginner · Batch A".
  /// A batch name alone is ambiguous - every course has a "Batch A".
  String get label => '$courseName · $batchName';

  factory FeeTypeBatchBinding.fromJson(Map<String, dynamic> json) => FeeTypeBatchBinding(
        batchId: json['batchId'] as String,
        batchName: json['batchName'] as String? ?? 'Batch',
        courseId: json['courseId'] as String? ?? '',
        courseName: json['courseName'] as String? ?? 'Unknown course',
      );
}

/// A named charge raised outside the regular course fee - costume, exam, annual day.
class FeeType {
  const FeeType({
    required this.id,
    required this.name,
    required this.amount,
    required this.batches,
    this.dueDate,
    this.defaultMode,
    this.active = true,
  });

  final String id;
  final String name;
  final num amount;

  /// The last date to pay. An unpaid fee past it reads as overdue. Null for an open-ended charge.
  final DateTime? dueDate;

  final String? defaultMode;
  final bool active;
  final List<FeeTypeBatchBinding> batches;

  /// A fee bound to exactly one batch is not a choice - the selector locks to it rather than
  /// making the admin open a menu with a single entry.
  FeeTypeBatchBinding? get onlyBatch => batches.length == 1 ? batches.first : null;

  factory FeeType.fromJson(Map<String, dynamic> json) => FeeType(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Fee',
        amount: json['amount'] as num? ?? 0,
        dueDate: DateTime.tryParse(json['dueDate'] as String? ?? ''),
        defaultMode: json['defaultMode'] as String?,
        active: json['active'] as bool? ?? true,
        batches: (json['batches'] as List<dynamic>? ?? [])
            .map((e) => FeeTypeBatchBinding.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
