import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/dashboard/data/dashboard_stats.dart';

final dashboardApiProvider = Provider((ref) => DashboardApi(ref.watch(dioClientProvider)));

/// Re-fetches whenever the caller switches which academy membership is active, same as
/// activeCoursesProvider - the stats row is meaningless without that context.
final dashboardStatsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(dashboardApiProvider).stats();
});

class DashboardApi {
  DashboardApi(this._client);
  final DioClient _client;

  Future<DashboardStats> stats() {
    return _client.call(
      (dio) => dio.get('/dashboard/stats'),
      (data) => DashboardStats.fromJson(data as Map<String, dynamic>),
    );
  }
}
