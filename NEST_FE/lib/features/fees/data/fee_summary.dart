/// One category's position on the fees landing.
class CategorySummary {
  const CategorySummary({
    required this.paidCount,
    required this.totalCount,
    required this.expected,
    required this.collected,
    required this.manualAmount,
    required this.gatewayAmount,
    required this.pending,
  });

  final int paidCount;
  final int totalCount;
  final num expected;
  final num collected;

  /// Cash and UPI together - the question they answer is the same: is it in the cash box rather
  /// than on the gateway statement.
  final num manualAmount;

  final num gatewayAmount;
  final num pending;

  /// Collected as a share of expected, 0-100. Guards a zero expected, which is a normal state for
  /// an academy that has not billed anything yet.
  double get percent =>
      expected <= 0 ? 0 : ((collected / expected) * 100).clamp(0, 100).toDouble();

  factory CategorySummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CategorySummary.zero();
    return CategorySummary(
      paidCount: json['paidCount'] as int? ?? 0,
      totalCount: json['totalCount'] as int? ?? 0,
      expected: json['expected'] as num? ?? 0,
      collected: json['collected'] as num? ?? 0,
      manualAmount: json['manualAmount'] as num? ?? 0,
      gatewayAmount: json['gatewayAmount'] as num? ?? 0,
      pending: json['pending'] as num? ?? 0,
    );
  }

  const CategorySummary.zero()
      : paidCount = 0,
        totalCount = 0,
        expected = 0,
        collected = 0,
        manualAmount = 0,
        gatewayAmount = 0,
        pending = 0;
}

/// Both categories, computed over the same filters so the two cards are comparable.
class FeeSummary {
  const FeeSummary({required this.regular, required this.other});

  final CategorySummary regular;
  final CategorySummary other;

  factory FeeSummary.fromJson(Map<String, dynamic> json) => FeeSummary(
        regular: CategorySummary.fromJson(json['regular'] as Map<String, dynamic>?),
        other: CategorySummary.fromJson(json['other'] as Map<String, dynamic>?),
      );
}

/// A student matched by the landing's search box.
class StudentSearchResult {
  const StudentSearchResult({
    required this.membershipId,
    required this.studentName,
    required this.context,
  });

  final String membershipId;
  final String studentName;
  final String context;

  factory StudentSearchResult.fromJson(Map<String, dynamic> json) => StudentSearchResult(
        membershipId: json['membershipId'] as String,
        studentName: json['studentName'] as String? ?? 'Unknown',
        context: json['context'] as String? ?? '',
      );
}
