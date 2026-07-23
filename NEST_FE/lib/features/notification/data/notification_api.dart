import 'package:nest_fe/core/network/dio_client.dart';

/// One in-app alert, shown in the Notifications tab. MEMBERSHIP_CONFIRMATION notifications carry
/// [actionCode] - the OTP the recipient reads aloud to whoever's completing their registration at
/// another academy/course (PRD 7.4 addendum's in-app delivery channel).
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final String? actionCode;
  final bool read;
  final String createdAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.actionCode,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
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

  Future<List<AppNotification>> list() {
    return _client.call(
      (dio) => dio.get('/notifications'),
      (data) => (data as List).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<void> markRead(String id) {
    return _client.callVoid((dio) => dio.post('/notifications/$id/read'));
  }
}
