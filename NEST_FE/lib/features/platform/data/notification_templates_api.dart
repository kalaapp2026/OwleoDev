import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';

/// Whether each channel can deliver right now. Push and WhatsApp need server-side credentials, so
/// the console says so plainly instead of letting an admin switch a channel on that goes nowhere.
class ChannelStatus {
  final bool inApp;
  final bool push;
  final bool whatsapp;

  const ChannelStatus({required this.inApp, required this.push, required this.whatsapp});

  factory ChannelStatus.fromJson(Map<String, dynamic> json) => ChannelStatus(
        inApp: json['inApp'] as bool? ?? true,
        push: json['push'] as bool? ?? false,
        whatsapp: json['whatsapp'] as bool? ?? false,
      );
}

/// What the Super Admin saved for one event.
class NotificationTemplate {
  final String title;
  final String body;
  final bool inAppEnabled;
  final bool pushEnabled;
  final bool whatsappEnabled;
  final String? whatsappTemplateName;
  final bool enabled;

  const NotificationTemplate({
    required this.title,
    required this.body,
    required this.inAppEnabled,
    required this.pushEnabled,
    required this.whatsappEnabled,
    required this.whatsappTemplateName,
    required this.enabled,
  });

  factory NotificationTemplate.fromJson(Map<String, dynamic> json) => NotificationTemplate(
        title: json['title'] as String,
        body: json['body'] as String,
        inAppEnabled: json['inAppEnabled'] as bool? ?? true,
        pushEnabled: json['pushEnabled'] as bool? ?? false,
        whatsappEnabled: json['whatsappEnabled'] as bool? ?? false,
        whatsappTemplateName: json['whatsappTemplateName'] as String?,
        enabled: json['enabled'] as bool? ?? true,
      );
}

/// One catalogued event. The catalogue lives on the server because an event only exists if some
/// service fires it; the console edits wording and channels, not which events exist.
class NotificationEventConfig {
  final String eventKey;
  final String module;
  final String label;
  final String description;
  final List<String> placeholders;
  final String defaultTitle;
  final String defaultBody;
  final NotificationTemplate? template;

  const NotificationEventConfig({
    required this.eventKey,
    required this.module,
    required this.label,
    required this.description,
    required this.placeholders,
    required this.defaultTitle,
    required this.defaultBody,
    required this.template,
  });

  bool get isConfigured => template != null;

  factory NotificationEventConfig.fromJson(Map<String, dynamic> json) => NotificationEventConfig(
        eventKey: json['eventKey'] as String,
        module: json['module'] as String,
        label: json['label'] as String,
        description: json['description'] as String? ?? '',
        placeholders: (json['placeholders'] as List).cast<String>(),
        defaultTitle: json['defaultTitle'] as String? ?? '',
        defaultBody: json['defaultBody'] as String? ?? '',
        template: json['template'] == null
            ? null
            : NotificationTemplate.fromJson(json['template'] as Map<String, dynamic>),
      );
}

class NotificationCatalog {
  final ChannelStatus channels;
  final List<NotificationEventConfig> events;

  const NotificationCatalog({required this.channels, required this.events});
}

class DeliveryLogEntry {
  final String recipientName;
  final String eventKey;
  final String channel;
  final String status;
  final String? detail;
  final DateTime createdAt;

  const DeliveryLogEntry({
    required this.recipientName,
    required this.eventKey,
    required this.channel,
    required this.status,
    required this.detail,
    required this.createdAt,
  });

  factory DeliveryLogEntry.fromJson(Map<String, dynamic> json) => DeliveryLogEntry(
        recipientName: json['recipientName'] as String? ?? 'Unknown',
        eventKey: json['eventKey'] as String,
        channel: json['channel'] as String,
        status: json['status'] as String,
        detail: json['detail'] as String?,
        // The server sends UTC without a zone suffix; without the Z, DateTime.parse reads it as
        // local time and the log shows every row hours off.
        createdAt: _parseUtc(json['createdAt'] as String),
      );

  static DateTime _parseUtc(String raw) =>
      DateTime.parse(raw.endsWith('Z') ? raw : '${raw}Z').toLocal();
}

class NotificationTemplatesApi {
  NotificationTemplatesApi(this._client);
  final DioClient _client;

  Future<NotificationCatalog> catalog() => _client.call(
        (dio) => dio.get('/admin/notification-templates'),
        (data) {
          final map = data as Map<String, dynamic>;
          return NotificationCatalog(
            channels: ChannelStatus.fromJson(map['channels'] as Map<String, dynamic>),
            events: (map['events'] as List)
                .map((e) => NotificationEventConfig.fromJson(e as Map<String, dynamic>))
                .toList(),
          );
        },
      );

  Future<void> save(
    String eventKey, {
    required String title,
    required String body,
    required bool inAppEnabled,
    required bool pushEnabled,
    required bool whatsappEnabled,
    required String? whatsappTemplateName,
    required bool enabled,
  }) =>
      _client.callVoid((dio) => dio.put('/admin/notification-templates/$eventKey', data: {
            'title': title,
            'body': body,
            'inAppEnabled': inAppEnabled,
            'pushEnabled': pushEnabled,
            'whatsappEnabled': whatsappEnabled,
            'whatsappTemplateName': whatsappTemplateName,
            'enabled': enabled,
          }));

  Future<void> remove(String eventKey) =>
      _client.callVoid((dio) => dio.delete('/admin/notification-templates/$eventKey'));

  Future<void> sendTest(String eventKey) =>
      _client.callVoid((dio) => dio.post('/admin/notification-templates/$eventKey/test'));

  Future<List<DeliveryLogEntry>> deliveries() => _client.call(
        (dio) => dio.get('/admin/notification-deliveries', queryParameters: {'limit': 100}),
        (data) => (data as List)
            .map((e) => DeliveryLogEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

final notificationTemplatesApiProvider =
    Provider((ref) => NotificationTemplatesApi(ref.watch(dioClientProvider)));

final notificationCatalogProvider = FutureProvider.autoDispose<NotificationCatalog>(
  (ref) => ref.watch(notificationTemplatesApiProvider).catalog(),
);

final deliveryLogProvider = FutureProvider.autoDispose<List<DeliveryLogEntry>>(
  (ref) => ref.watch(notificationTemplatesApiProvider).deliveries(),
);
