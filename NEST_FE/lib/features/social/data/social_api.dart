import 'dart:typed_data';

import 'package:dio/dio.dart';
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

  /// Every post this person has ever made, under any identity they post as (their own Artist
  /// account, or an academy they're Admin/Trainer for) - backs both "My Posts" (own userId) and
  /// viewing someone else's profile from Search.
  Future<List<Post>> postsByUser(String userId) {
    return _client.call(
      (dio) => dio.get('/posts/by-user/$userId'),
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

  /// Call once per image - a multi-photo post is built by calling this repeatedly after create().
  Future<Post> addMedia(String postId, Uint8List bytes, String filename) {
    final formData = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)});
    return _client.call(
      (dio) => dio.post('/posts/$postId/media', data: formData),
      (data) => Post.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deletePost(String postId) {
    return _client.callVoid((dio) => dio.delete('/posts/$postId'));
  }

  Future<void> markInterest({String? eventId, String? postId}) {
    return _client.callVoid((dio) => dio.post('/interests', data: {'eventId': eventId, 'postId': postId}));
  }
}
