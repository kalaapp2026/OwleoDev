import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/messages/data/broadcast.dart';

final messagesApiProvider = Provider((ref) => MessagesApi(ref.watch(dioClientProvider)));

final sentBroadcastsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(messagesApiProvider).list();
});

class MessagesApi {
  MessagesApi(this._client);
  final DioClient _client;

  Future<Broadcast> create({
    required String title,
    required String body,
    required String audienceType,
    Set<String> courseIds = const {},
    Set<String> batchIds = const {},
    Set<String> individualIds = const {},
  }) {
    return _client.call(
      (dio) => dio.post('/academies/me/broadcasts', data: {
        'title': title,
        'body': body,
        'audienceType': audienceType,
        'courseIds': courseIds.toList(),
        'batchIds': batchIds.toList(),
        'individualIds': individualIds.toList(),
      }),
      (data) => Broadcast.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<List<Broadcast>> list() {
    return _client.call(
      (dio) => dio.get('/academies/me/broadcasts'),
      (data) => (data as List).map((e) => Broadcast.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
