import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';

final academySettingsApiProvider = Provider((ref) => AcademySettingsApi(ref.watch(dioClientProvider)));

/// Each of these re-fetches when the caller switches academy membership, like every other
/// academy-scoped provider here.
final academySettingsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(academySettingsApiProvider).settings();
});

final subscriptionProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(academySettingsApiProvider).subscription();
});

final myAcademyRequestsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(academySettingsApiProvider).myRequests();
});

final recentExportsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(academySettingsApiProvider).recentExports();
});

/// The Super Admin's inbox: every academy's requests, optionally one status.
final allAcademyRequestsProvider = FutureProvider.autoDispose.family<List<AcademyRequest>, String?>((ref, status) {
  return ref.watch(academySettingsApiProvider).allRequests(status: status);
});

class AcademySettings {
  const AcademySettings({required this.academyId, required this.name, required this.ownerName, required this.defaultLanguage});

  final String academyId;
  final String name;
  final String? ownerName;
  final String defaultLanguage;

  factory AcademySettings.fromJson(Map<String, dynamic> json) => AcademySettings(
        academyId: json['academyId'] as String,
        name: json['name'] as String? ?? '',
        ownerName: json['ownerName'] as String?,
        defaultLanguage: json['defaultLanguage'] as String? ?? 'en',
      );
}

/// A billing plan. A null limit means the plan has no cap on that count.
class PlanSummary {
  const PlanSummary({required this.code, required this.displayName, required this.monthlyPrice, required this.maxStudents, required this.maxTrainers});

  final String code;
  final String displayName;
  final num? monthlyPrice;
  final int? maxStudents;
  final int? maxTrainers;

  factory PlanSummary.fromJson(Map<String, dynamic> json) => PlanSummary(
        code: json['code'] as String,
        displayName: json['displayName'] as String? ?? json['code'] as String,
        monthlyPrice: json['monthlyPrice'] as num?,
        maxStudents: json['maxStudents'] as int?,
        maxTrainers: json['maxTrainers'] as int?,
      );
}

class Subscription {
  const Subscription({required this.current, required this.students, required this.trainers, required this.plans});

  final PlanSummary current;
  final int students;
  final int trainers;
  final List<PlanSummary> plans;

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        current: PlanSummary.fromJson(json['current'] as Map<String, dynamic>),
        students: (json['students'] as num?)?.toInt() ?? 0,
        trainers: (json['trainers'] as num?)?.toInt() ?? 0,
        plans: (json['plans'] as List? ?? const []).map((e) => PlanSummary.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// What kind of thing an academy is asking the platform team for - the backend's
/// AcademyRequestType, by wire name.
enum AcademyRequestKind {
  ownershipTransfer('OWNERSHIP_TRANSFER', 'Ownership transfer'),
  planChange('PLAN_CHANGE', 'Plan change'),
  cancelSubscription('CANCEL_SUBSCRIPTION', 'Cancel subscription'),
  academyClosure('ACADEMY_CLOSURE', 'Academy closure'),
  support('SUPPORT', 'Support message');

  const AcademyRequestKind(this.wire, this.label);

  final String wire;
  final String label;

  static AcademyRequestKind fromWire(String? value) =>
      AcademyRequestKind.values.firstWhere((k) => k.wire == value, orElse: () => AcademyRequestKind.support);
}

class AcademyRequest {
  const AcademyRequest({
    required this.id,
    required this.academyName,
    required this.requestedByName,
    required this.kind,
    required this.status,
    required this.subject,
    required this.details,
    required this.targetEmail,
    required this.reason,
    required this.targetPlan,
    required this.resolutionNote,
    required this.createdAt,
    required this.resolvedAt,
  });

  final String id;
  final String? academyName;
  final String? requestedByName;
  final AcademyRequestKind kind;

  /// PENDING, APPROVED or DECLINED.
  final String status;
  final String? subject;
  final String? details;
  final String? targetEmail;
  final String? reason;
  final String? targetPlan;
  final String? resolutionNote;
  final String createdAt;
  final String? resolvedAt;

  bool get isPending => status == 'PENDING';

  factory AcademyRequest.fromJson(Map<String, dynamic> json) => AcademyRequest(
        id: json['id'] as String,
        academyName: json['academyName'] as String?,
        requestedByName: json['requestedByName'] as String?,
        kind: AcademyRequestKind.fromWire(json['type'] as String?),
        status: json['status'] as String? ?? 'PENDING',
        subject: json['subject'] as String?,
        details: json['details'] as String?,
        targetEmail: json['targetEmail'] as String?,
        reason: json['reason'] as String?,
        targetPlan: json['targetPlan'] as String?,
        resolutionNote: json['resolutionNote'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
        resolvedAt: json['resolvedAt'] as String?,
      );
}

class ExportRecord {
  const ExportRecord({required this.id, required this.kind, required this.fileName, required this.rowCount, required this.sizeBytes, required this.createdAt});

  final String id;
  final String kind;
  final String fileName;
  final int rowCount;
  final int sizeBytes;
  final String createdAt;

  factory ExportRecord.fromJson(Map<String, dynamic> json) => ExportRecord(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        rowCount: (json['rowCount'] as num?)?.toInt() ?? 0,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] as String? ?? '',
      );
}

/// A downloaded export: the CSV bytes and the name the server gave it.
class ExportFile {
  const ExportFile({required this.fileName, required this.bytes});
  final String fileName;
  final List<int> bytes;
}

class AcademySettingsApi {
  AcademySettingsApi(this._client);
  final DioClient _client;

  Future<AcademySettings> settings() => _client.call(
        (dio) => dio.get('/academies/me/settings'),
        (data) => AcademySettings.fromJson(data as Map<String, dynamic>),
      );

  Future<AcademySettings> updateLanguage(String languageCode) => _client.call(
        (dio) => dio.put('/academies/me/settings/language', data: {'defaultLanguage': languageCode}),
        (data) => AcademySettings.fromJson(data as Map<String, dynamic>),
      );

  Future<Subscription> subscription() => _client.call(
        (dio) => dio.get('/academies/me/subscription'),
        (data) => Subscription.fromJson(data as Map<String, dynamic>),
      );

  Future<AcademyRequest> submitRequest({
    required AcademyRequestKind kind,
    String? subject,
    String? details,
    String? targetEmail,
    String? reason,
    String? targetPlan,
  }) =>
      _client.call(
        (dio) => dio.post('/academies/me/requests', data: {
          'type': kind.wire,
          'subject': subject,
          'details': details,
          'targetEmail': targetEmail,
          'reason': reason,
          'targetPlan': targetPlan,
        }),
        (data) => AcademyRequest.fromJson(data as Map<String, dynamic>),
      );

  Future<List<AcademyRequest>> myRequests() => _client.call(
        (dio) => dio.get('/academies/me/requests'),
        (data) => (data as List).map((e) => AcademyRequest.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Future<List<ExportRecord>> recentExports() => _client.call(
        (dio) => dio.get('/academies/me/exports'),
        (data) => (data as List).map((e) => ExportRecord.fromJson(e as Map<String, dynamic>)).toList(),
      );

  /// [kind] is `students`, `fees` or `attendance`; the bytes are the CSV.
  Future<ExportFile> downloadExport(String kind) {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return _client.call(
      (dio) => dio.get<List<int>>('/academies/me/exports/$kind', options: Options(responseType: ResponseType.bytes)),
      (data) => ExportFile(fileName: '$kind-$date.csv', bytes: (data as List).cast<int>()),
    );
  }

  Future<List<AcademyRequest>> allRequests({String? status}) => _client.call(
        (dio) => dio.get('/admin/academy-requests', queryParameters: {'status': ?status}),
        (data) => (data as List).map((e) => AcademyRequest.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Future<AcademyRequest> resolveRequest(String id, {required bool approve, String? note}) => _client.call(
        (dio) => dio.patch('/admin/academy-requests/$id', data: {'approve': approve, 'note': note}),
        (data) => AcademyRequest.fromJson(data as Map<String, dynamic>),
      );
}
