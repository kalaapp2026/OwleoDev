import 'package:nest_fe/core/network/dio_client.dart';

/// The two post-login worlds a notification can belong to. The ERP bell only shows ERP items,
/// the Social bell only shows Social ones - kept as an enum so the wrong module can never be
/// requested by a typo'd string.
enum NotificationModule {
  social,
  erp;

  String get wire => name.toUpperCase(); // SOCIAL / ERP
}

/// One in-app alert. MEMBERSHIP_CONFIRMATION notifications carry [actionCode] - the OTP the
/// recipient reads aloud to whoever's completing their registration (PRD 7.4 addendum's in-app
/// delivery channel). ADMIN_BROADCAST notifications are Super Admin announcements.
class AppNotification {
  final String id;
  final String module;
  final String type;
  final String title;
  final String body;
  final String? actionCode;
  final bool read;
  final String createdAt;

  AppNotification({
    required this.id,
    required this.module,
    required this.type,
    required this.title,
    required this.body,
    required this.actionCode,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        module: json['module'] as String? ?? 'ERP',
        type: json['type'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        actionCode: json['actionCode'] as String?,
        read: json['read'] as bool? ?? false,
        createdAt: json['createdAt'] as String,
      );
}

class NotificationApi {
  NotificationApi(this._client);
  final DioClient _client;

  Future<List<AppNotification>> list(NotificationModule module) {
    return _client.call(
      (dio) => dio.get('/notifications', queryParameters: {'module': module.wire}),
      (data) => (data as List).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<int> unreadCount(NotificationModule module) {
    return _client.call(
      (dio) => dio.get('/notifications/unread-count', queryParameters: {'module': module.wire}),
      (data) => (data as Map<String, dynamic>)['count'] as int? ?? 0,
    );
  }

  Future<void> markRead(String id) {
    return _client.callVoid((dio) => dio.post('/notifications/$id/read'));
  }

  /// Super Admin console. [audience] is 'EVERYONE' or 'ACADEMY' (which needs [academyId]).
  /// Returns how many recipients it reached.
  Future<int> broadcast({
    required NotificationModule module,
    required String audience,
    String? academyId,
    required String title,
    required String body,
  }) {
    return _client.call(
      (dio) => dio.post('/admin/notifications/broadcast', data: {
        'module': module.wire,
        'audience': audience,
        'academyId': academyId,
        'title': title,
        'body': body,
      }),
      (data) => (data as Map<String, dynamic>)['recipients'] as int? ?? 0,
    );
  }
}
