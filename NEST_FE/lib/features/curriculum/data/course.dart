import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/format/money.dart';

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

/// The label on the billing-type segmented control.
String feeModelLabel(FeeModel model) => switch (model) {
      FeeModel.fixed => 'Fixed',
      FeeModel.perClass => 'Per-class',
      FeeModel.hybrid => 'Hybrid',
    };

/// The one-line explanation shown under the segmented control, so the choice is made on what it
/// means rather than on the word alone.
String feeModelHint(FeeModel model) => switch (model) {
      FeeModel.fixed => 'One flat fee per billing cycle, regardless of classes attended.',
      FeeModel.perClass => 'Fee is calculated per individual session attended.',
      FeeModel.hybrid => 'A base fee, discounted if attendance falls below a threshold.',
    };

/// How often a fixed/hybrid course bills. Per-class courses have no cycle - they bill on
/// attendance - which is why the picker hides for that model.
enum FeeCycle {
  monthly('MONTHLY', 'Monthly', 1),
  quarterly('QUARTERLY', 'Quarterly', 3),
  halfYearly('HALF_YEARLY', 'Half-Yearly', 6),
  yearly('YEARLY', 'Yearly', 12);

  const FeeCycle(this.wire, this.label, this.months);

  final String wire;
  final String label;

  /// Months per cycle, used to show the amount actually charged each time.
  final int months;

  static FeeCycle fromWire(String? value) =>
      values.firstWhere((c) => c.wire == value, orElse: () => FeeCycle.monthly);
}

/// Methods an academy can accept for a course's fees.
enum PaymentMethod {
  cash('CASH', 'Cash'),
  upi('UPI', 'UPI'),
  gateway('GATEWAY', 'Gateway');

  const PaymentMethod(this.wire, this.label);

  final String wire;
  final String label;

  static PaymentMethod? fromWire(String value) {
    for (final m in values) {
      if (m.wire == value) return m;
    }
    return null;
  }
}

class Course {
  final String id;
  final String academyId;
  final CourseCategory category;
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
  final FeeCycle feeCycle;
  final String? thumbnailUrl;
  final String status;
  final int? billingDayOfMonth;
  final int? dueDayOfMonth;
  final Set<PaymentMethod> paymentMethods;
  final String? iconKey;

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
    required this.dueDayOfMonth,
    required this.paymentMethods,
    required this.iconKey,
  });

  bool get isActive => status == 'ACTIVE';

  /// Human-readable summary of when fee slips auto-generate, for the course list/edit form.
  String? get billingSummary => billingDayOfMonth == null
      ? null
      : 'Fee slip generated on the ${ordinalDay(billingDayOfMonth!)} of each month';

  /// The list row's fee line. Deliberately terse - a course row shows category and price at a
  /// glance, and the full hybrid formula belongs on the edit form where there's room to explain
  /// it, not crammed into a subtitle.
  String get feeSummary => switch (feeModel) {
        FeeModel.perClass => '${money(feePerClass ?? 0)}/class',
        FeeModel.hybrid => '${money(defaultFee ?? 0)} base · hybrid',
        FeeModel.fixed => '${money(defaultFee ?? 0)}/mo',
      };

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as String,
        academyId: json['academyId'] as String,
        category: CourseCategory.fromWire(json['category'] as String?),
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
        feeCycle: FeeCycle.fromWire(json['feeCycle'] as String?),
        thumbnailUrl: json['thumbnailUrl'] as String?,
        status: json['status'] as String,
        billingDayOfMonth: json['billingDayOfMonth'] as int?,
        dueDayOfMonth: json['dueDayOfMonth'] as int?,
        // An unrecognised method is dropped rather than failing the whole course: a server that
        // grows a new method shouldn't make existing courses unopenable in an older build.
        paymentMethods: ((json['paymentMethods'] as List?) ?? const [])
            .map((m) => PaymentMethod.fromWire(m as String))
            .whereType<PaymentMethod>()
            .toSet(),
        iconKey: json['iconKey'] as String?,
      );
}
