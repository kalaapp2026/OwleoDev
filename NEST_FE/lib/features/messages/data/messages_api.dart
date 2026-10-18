import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/messages/data/broadcast.dart';

final messagesApiProvider = Provider((ref) => MessagesApi(ref.watch(dioClientProvider)));

final sentBroadcastsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(messagesApiProvider).list();
});

final broadcastDetailProvider = FutureProvider.autoDispose.family<BroadcastDetail, String>((ref, id) {
  return ref.watch(messagesApiProvider).detail(id);
});

class MessagesApi {
  MessagesApi(this._client);
  final DioClient _client;

  Map<String, dynamic> _audience(String audienceType, Set<String> courseIds, Set<String> batchIds, Set<String> individualIds) => {
        'audienceType': audienceType,
        'courseIds': courseIds.toList(),
        'batchIds': batchIds.toList(),
        'individualIds': individualIds.toList(),
      };

  Future<Broadcast> create({
    required String body,
    required String audienceType,
    Set<String> courseIds = const {},
    Set<String> batchIds = const {},
    Set<String> individualIds = const {},
  }) {
    return _client.call(
      (dio) => dio.post('/academies/me/broadcasts', data: {
        'body': body,
        ..._audience(audienceType, courseIds, batchIds, individualIds),
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

  Future<BroadcastDetail> detail(String id) {
    return _client.call(
      (dio) => dio.get('/academies/me/broadcasts/$id'),
      (data) => BroadcastDetail.fromJson(data as Map<String, dynamic>),
    );
  }

  /// How many people this audience would reach right now.
  Future<int> previewRecipientCount({
    required String audienceType,
    Set<String> courseIds = const {},
    Set<String> batchIds = const {},
    Set<String> individualIds = const {},
  }) {
    return _client.call(
      (dio) => dio.post('/academies/me/broadcasts/preview', data: _audience(audienceType, courseIds, batchIds, individualIds)),
      (data) => (data as Map<String, dynamic>)['recipientCount'] as int? ?? 0,
    );
  }
}
