import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/features/events/data/event.dart';

class EventsApi {
  EventsApi(this._client);
  final DioClient _client;

  Future<List<Event>> publicEvents() {
    return _client.call(
      (dio) => dio.get('/events/public'),
      (data) => (data as List).map((e) => Event.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<List<Event>> forAcademy(String academyId) {
    return _client.call(
      (dio) => dio.get('/academies/$academyId/events'),
      (data) => (data as List).map((e) => Event.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<Event> get(String id) {
    return _client.call(
      (dio) => dio.get('/events/$id'),
      (data) => Event.fromJson(data as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> _body({
    required String type,
    required String title,
    String? description,
    required String eventDate,
    String? endDate,
    String? location,
    String? venueMapsUrl,
    required String visibility,
    String? coverImageUrl,
    String? interestDeadline,
    required String audienceType,
    required Set<String> courseIds,
    required Set<String> batchIds,
    required Set<String> individualIds,
  }) =>
      {
        'type': type,
        'title': title,
        'description': description,
        'eventDate': eventDate,
        'endDate': endDate,
        'location': location,
        'venueMapsUrl': venueMapsUrl,
        'visibility': visibility,
        'coverImageUrl': coverImageUrl,
        'interestDeadline': interestDeadline,
        'audienceType': audienceType,
        'courseIds': courseIds.toList(),
        'batchIds': batchIds.toList(),
        'individualIds': individualIds.toList(),
      };

  Future<Event> create({
    required String type,
    required String title,
    String? description,
    required String eventDate,
    String? endDate,
    String? location,
    String? venueMapsUrl,
    required String visibility,
    String? coverImageUrl,
    String? interestDeadline,
    String status = 'PUBLISHED',
    String audienceType = 'ALL_STUDENTS',
    Set<String> courseIds = const {},
    Set<String> batchIds = const {},
    Set<String> individualIds = const {},
  }) {
    return _client.call(
      (dio) => dio.post('/events', data: {
        ..._body(
          type: type,
          title: title,
          description: description,
          eventDate: eventDate,
          endDate: endDate,
          location: location,
          venueMapsUrl: venueMapsUrl,
          visibility: visibility,
          coverImageUrl: coverImageUrl,
          interestDeadline: interestDeadline,
          audienceType: audienceType,
          courseIds: courseIds,
          batchIds: batchIds,
          individualIds: individualIds,
        ),
        'status': status,
      }),
      (data) => Event.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Status is deliberately not editable here - it only ever changes via [updateStatus], so an
  /// edit can never accidentally cancel or publish an event.
  Future<Event> update({
    required String id,
    required String type,
    required String title,
    String? description,
    required String eventDate,
    String? endDate,
    String? location,
    String? venueMapsUrl,
    required String visibility,
    String? coverImageUrl,
    String? interestDeadline,
    required String audienceType,
    Set<String> courseIds = const {},
    Set<String> batchIds = const {},
    Set<String> individualIds = const {},
  }) {
    return _client.call(
      (dio) => dio.put('/events/$id',
          data: _body(
            type: type,
            title: title,
            description: description,
            eventDate: eventDate,
            endDate: endDate,
            location: location,
            venueMapsUrl: venueMapsUrl,
            visibility: visibility,
            coverImageUrl: coverImageUrl,
            interestDeadline: interestDeadline,
            audienceType: audienceType,
            courseIds: courseIds,
            batchIds: batchIds,
            individualIds: individualIds,
          )),
      (data) => Event.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<Event> updateStatus(String id, String status) {
    return _client.call(
      (dio) => dio.patch('/events/$id/status', data: {'status': status}),
      (data) => Event.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> delete(String id) {
    return _client.callVoid((dio) => dio.delete('/events/$id'));
  }

  Future<EventInterests> interestsFor(String id) {
    return _client.call(
      (dio) => dio.get('/events/$id/interests'),
      (data) => EventInterests.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> markInterested(String eventId) {
    return _client.callVoid((dio) => dio.post('/interests', data: {'eventId': eventId, 'postId': null}));
  }
}
