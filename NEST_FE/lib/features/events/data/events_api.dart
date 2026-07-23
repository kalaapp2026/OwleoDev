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

  Future<Event> create({
    required String type,
    required String title,
    String? description,
    required String eventDate,
    String? location,
    required String visibility,
    String? coverImageUrl,
  }) {
    return _client.call(
      (dio) => dio.post('/events', data: {
        'type': type,
        'title': title,
        'description': description,
        'eventDate': eventDate,
        'location': location,
        'visibility': visibility,
        'coverImageUrl': coverImageUrl,
      }),
      (data) => Event.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> markInterested(String eventId) {
    return _client.callVoid((dio) => dio.post('/interests', data: {'eventId': eventId, 'postId': null}));
  }
}
