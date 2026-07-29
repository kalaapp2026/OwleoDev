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

/// One academy as the Super Admin console sees it - identity plus the headline counts. Distinct
/// from [AcademyStats] above, which is the platform-wide roll-up (how many academies exist).
class AcademySummary {
  final String id;
  final String name;
  final String? city;
  final String status;
  final String? plan;
  final DateTime? createdAt;

  /// Newest activity across this academy's members. Null means nobody has opened the app since
  /// activity tracking started - shown as "no activity yet" rather than faked as zero.
  final DateTime? lastActivityAt;

  final int students;
  final int trainers;
  final int admins;
  final int courses;
  final int batches;
  final int events;
  final int posts;

  /// The academy's own revenue from its students - not what it owes the platform.
  final double feesCollected;

  const AcademySummary({
    required this.id,
    required this.name,
    required this.city,
    required this.status,
    required this.plan,
    required this.createdAt,
    required this.lastActivityAt,
    required this.students,
    required this.trainers,
    required this.admins,
    required this.courses,
    required this.batches,
    required this.events,
    required this.posts,
    required this.feesCollected,
  });

  bool get isSuspended => status == 'SUSPENDED';

  int get people => students + trainers + admins;

  factory AcademySummary.fromJson(Map<String, dynamic> json) => AcademySummary(
        id: json['id'] as String,
        name: json['name'] as String,
        city: json['city'] as String?,
        status: json['status'] as String? ?? 'ACTIVE',
        plan: json['plan'] as String?,
        createdAt: json['createdAt'] == null ? null : DateTime.parse(json['createdAt'] as String),
        lastActivityAt:
            json['lastActivityAt'] == null ? null : DateTime.parse(json['lastActivityAt'] as String),
        students: (json['students'] as num?)?.toInt() ?? 0,
        trainers: (json['trainers'] as num?)?.toInt() ?? 0,
        admins: (json['admins'] as num?)?.toInt() ?? 0,
        courses: (json['courses'] as num?)?.toInt() ?? 0,
        batches: (json['batches'] as num?)?.toInt() ?? 0,
        events: (json['events'] as num?)?.toInt() ?? 0,
        posts: (json['posts'] as num?)?.toInt() ?? 0,
        feesCollected: (json['feesCollected'] as num?)?.toDouble() ?? 0,
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

  Future<List<AcademySummary>> academies() {
    return _client.call(
      (dio) => dio.get('/admin/platform/academies'),
      (data) => (data as List).map((e) => AcademySummary.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<AcademySummary> academy(String academyId) {
    return _client.call(
      (dio) => dio.get('/admin/platform/academies/$academyId'),
      (data) => AcademySummary.fromJson(data as Map<String, dynamic>),
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
