import 'package:nest_fe/core/network/dio_client.dart';

/// Super Admin console figures - everything the platform dashboard shows, in one call.
class PlatformOverview {
  final AcademyStats academies;
  final UserStats users;
  final ActivityStats activity;
  final SocialStats social;
  final List<DailyCount> signupTrend;

  const PlatformOverview({
    required this.academies,
    required this.users,
    required this.activity,
    required this.social,
    required this.signupTrend,
  });

  factory PlatformOverview.fromJson(Map<String, dynamic> json) => PlatformOverview(
        academies: AcademyStats.fromJson(json['academies'] as Map<String, dynamic>),
        users: UserStats.fromJson(json['users'] as Map<String, dynamic>),
        activity: ActivityStats.fromJson(json['activity'] as Map<String, dynamic>),
        social: SocialStats.fromJson(json['social'] as Map<String, dynamic>),
        signupTrend: (json['signupTrend'] as List? ?? [])
            .map((e) => DailyCount.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AcademyStats {
  final int total;
  final int active;
  final int suspended;
  final int newThisMonth;

  const AcademyStats({
    required this.total,
    required this.active,
    required this.suspended,
    required this.newThisMonth,
  });

  factory AcademyStats.fromJson(Map<String, dynamic> json) => AcademyStats(
        total: json['total'] as int? ?? 0,
        active: json['active'] as int? ?? 0,
        suspended: json['suspended'] as int? ?? 0,
        newThisMonth: json['newThisMonth'] as int? ?? 0,
      );
}

class UserStats {
  final int total;
  final Map<String, int> byRole;
  final int newThisWeek;
  final int newThisMonth;

  const UserStats({
    required this.total,
    required this.byRole,
    required this.newThisWeek,
    required this.newThisMonth,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) => UserStats(
        total: json['total'] as int? ?? 0,
        byRole: (json['byRole'] as Map<String, dynamic>? ?? {})
            .map((key, value) => MapEntry(key, (value as num).toInt())),
        newThisWeek: json['newThisWeek'] as int? ?? 0,
        newThisMonth: json['newThisMonth'] as int? ?? 0,
      );
}

class ActivityStats {
  final int activeLastHour;
  final int activeToday;
  final int activeThisWeek;
  final int activeThisMonth;

  /// Distinct devices that have launched the app - a proxy for store downloads, which the backend
  /// cannot see. The UI labels it "installs seen" rather than "downloads" for that reason.
  final int installsSeen;

  const ActivityStats({
    required this.activeLastHour,
    required this.activeToday,
    required this.activeThisWeek,
    required this.activeThisMonth,
    required this.installsSeen,
  });

  factory ActivityStats.fromJson(Map<String, dynamic> json) => ActivityStats(
        activeLastHour: json['activeLastHour'] as int? ?? 0,
        activeToday: json['activeToday'] as int? ?? 0,
        activeThisWeek: json['activeThisWeek'] as int? ?? 0,
        activeThisMonth: json['activeThisMonth'] as int? ?? 0,
        installsSeen: json['installsSeen'] as int? ?? 0,
      );
}

class SocialStats {
  final int totalPosts;
  final int postsThisWeek;
  final int totalEvents;
  final int upcomingEvents;
  final int pendingArtistApplications;

  const SocialStats({
    required this.totalPosts,
    required this.postsThisWeek,
    required this.totalEvents,
    required this.upcomingEvents,
    required this.pendingArtistApplications,
  });

  factory SocialStats.fromJson(Map<String, dynamic> json) => SocialStats(
        totalPosts: json['totalPosts'] as int? ?? 0,
        postsThisWeek: json['postsThisWeek'] as int? ?? 0,
        totalEvents: json['totalEvents'] as int? ?? 0,
        upcomingEvents: json['upcomingEvents'] as int? ?? 0,
        pendingArtistApplications: json['pendingArtistApplications'] as int? ?? 0,
      );
}

class DailyCount {
  final DateTime day;
  final int count;

  const DailyCount({required this.day, required this.count});

  factory DailyCount.fromJson(Map<String, dynamic> json) => DailyCount(
        day: DateTime.parse(json['day'] as String),
        count: (json['count'] as num).toInt(),
      );
}

class PlatformApi {
  PlatformApi(this._client);
  final DioClient _client;

  Future<PlatformOverview> overview() {
    return _client.call(
      (dio) => dio.get('/admin/platform/overview'),
      (data) => PlatformOverview.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Fire-and-forget install counting, called once per launch before login is required.
  Future<void> pingDevice({required String deviceId, required String platform, required String appVersion}) {
    return _client.callVoid((dio) => dio.post('/devices/ping', data: {
          'deviceId': deviceId,
          'platform': platform,
          'appVersion': appVersion,
        }));
  }
}
