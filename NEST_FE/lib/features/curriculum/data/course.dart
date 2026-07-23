/// NEST Course Fee Calculation Spec §2 - how a course's fee is calculated from attendance.
enum FeeModel { perClass, fixed, hybrid }

FeeModel feeModelFromString(String value) => switch (value) {
      'PER_CLASS' => FeeModel.perClass,
      'HYBRID' => FeeModel.hybrid,
      _ => FeeModel.fixed,
    };

String feeModelToApiString(FeeModel model) => switch (model) {
      FeeModel.perClass => 'PER_CLASS',
      FeeModel.fixed => 'FIXED',
      FeeModel.hybrid => 'HYBRID',
    };

class Course {
  final String id;
  final String academyId;
  final String category;
  final String name;
  final String? description;
  final String? durationLevel;
  final FeeModel feeModel;
  final num? defaultFee;
  final num? feePerClass;
  final int? hybridExpectedClassesPerPeriod;
  final int? hybridThresholdAttendance;
  final int hybridFeeAboveThresholdPercent;
  final int? hybridFeeBelowThresholdPercent;
  final num? hybridMinFeeAmount;
  final String feeCycle;
  final String? thumbnailUrl;
  final String status;
  final int? billingDayOfMonth;

  const Course({
    required this.id,
    required this.academyId,
    required this.category,
    required this.name,
    required this.description,
    required this.durationLevel,
    required this.feeModel,
    required this.defaultFee,
    required this.feePerClass,
    required this.hybridExpectedClassesPerPeriod,
    required this.hybridThresholdAttendance,
    required this.hybridFeeAboveThresholdPercent,
    required this.hybridFeeBelowThresholdPercent,
    required this.hybridMinFeeAmount,
    required this.feeCycle,
    required this.thumbnailUrl,
    required this.status,
    required this.billingDayOfMonth,
  });

  bool get isActive => status == 'ACTIVE';

  /// Human-readable summary of when fee slips auto-generate, for the course list/edit form.
  String? get billingSummary =>
      billingDayOfMonth == null ? null : 'Fee slip generated on the ${ordinalDay(billingDayOfMonth!)} of each month';

  /// "2" -> "2nd", "23" -> "23rd" - shared by the list summary and the day-of-month picker.
  static String ordinalDay(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }

  /// One-line summary of what this course charges, for list rows - mirrors the "formula shown"
  /// language from the Fee Calculation Spec so the same phrasing appears everywhere.
  String get feeSummary => switch (feeModel) {
        FeeModel.perClass => '₹$feePerClass/class',
        FeeModel.fixed => '₹$defaultFee/${feeCycle.toLowerCase()}',
        FeeModel.hybrid =>
          '₹$defaultFee/${feeCycle.toLowerCase()} (≥$hybridThresholdAttendance classes), else $hybridFeeBelowThresholdPercent%',
      };

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as String,
        academyId: json['academyId'] as String,
        category: json['category'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        durationLevel: json['durationLevel'] as String?,
        feeModel: feeModelFromString(json['feeModel'] as String? ?? 'FIXED'),
        defaultFee: json['defaultFee'] as num?,
        feePerClass: json['feePerClass'] as num?,
        hybridExpectedClassesPerPeriod: json['hybridExpectedClassesPerPeriod'] as int?,
        hybridThresholdAttendance: json['hybridThresholdAttendance'] as int?,
        hybridFeeAboveThresholdPercent: json['hybridFeeAboveThresholdPercent'] as int? ?? 100,
        hybridFeeBelowThresholdPercent: json['hybridFeeBelowThresholdPercent'] as int?,
        hybridMinFeeAmount: json['hybridMinFeeAmount'] as num?,
        feeCycle: json['feeCycle'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        status: json['status'] as String,
        billingDayOfMonth: json['billingDayOfMonth'] as int?,
      );
}
