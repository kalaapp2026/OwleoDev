import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/features/social/data/post.dart';

class SocialApi {
  SocialApi(this._client);
  final DioClient _client;

  Future<List<Post>> feed() {
    return _client.call(
      (dio) => dio.get('/feed'),
      (data) => (data as List).map((e) => Post.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<Post> createPost({required String content, required String visibility}) {
    return _client.call(
      (dio) => dio.post('/posts', data: {
        'type': 'NORMAL',
        'content': content,
        'mediaUrls': <String>[],
        'visibility': visibility,
        'eventId': null,
      }),
      (data) => Post.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> markInterest({String? eventId, String? postId}) {
    return _client.callVoid((dio) => dio.post('/interests', data: {'eventId': eventId, 'postId': postId}));
  }
}
