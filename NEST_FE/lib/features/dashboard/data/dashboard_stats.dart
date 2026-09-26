/// The Dashboard's stats row: headcounts for the caller's active academy. Aggregate totals only,
/// not rosters - see the backend DashboardStatsResponse doc comment for why that distinction
/// matters here.
class DashboardStats {
  const DashboardStats({
    required this.activeCourses,
    required this.activeBatches,
    required this.totalStudents,
    required this.totalTrainers,
  });

  final int activeCourses;
  final int activeBatches;
  final int totalStudents;
  final int totalTrainers;

  factory DashboardStats.fromJson(Map<String, dynamic> json) => DashboardStats(
        activeCourses: json['activeCourses'] as int? ?? 0,
        activeBatches: json['activeBatches'] as int? ?? 0,
        totalStudents: json['totalStudents'] as int? ?? 0,
        totalTrainers: json['totalTrainers'] as int? ?? 0,
      );
}
