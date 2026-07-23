import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/scheduling/data/calendar_class.dart';

final calendarApiProvider = Provider((ref) => CalendarApi(ref.watch(dioClientProvider)));

class CalendarApi {
  CalendarApi(this._client);
  final DioClient _client;

  /// Merged across every academy the caller belongs to (PRD 7.5) - not scoped to just the
  /// active academy the way most other endpoints are, so switching academies never hides classes
  /// here the way it would everywhere else in the app.
  Future<List<CalendarClass>> classesInRange({required String from, required String to}) {
    return _client.call(
      (dio) => dio.get('/calendar/classes', queryParameters: {'from': from, 'to': to}),
      (data) => (data as List).map((e) => CalendarClass.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
