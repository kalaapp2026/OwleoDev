import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/profile/data/self_profile.dart';

class SelfProfileApi {
  SelfProfileApi(this._client);
  final DioClient _client;

  SelfProfile _profile(dynamic d) => SelfProfile.fromJson(d as Map<String, dynamic>);

  Future<SelfProfile> get() => _client.call((dio) => dio.get('/users/me/profile'), _profile);

  /// Staff view of a student, from More > Students.
  Future<StudentProfile> forStudent(String membershipId) => _client.call(
        (dio) => dio.get('/students/$membershipId/profile'),
        (d) => StudentProfile.fromJson(d as Map<String, dynamic>),
      );

  Future<SelfProfile> update(Map<String, dynamic> body) =>
      _client.call((dio) => dio.put('/users/me/profile', data: body), _profile);

  Future<SelfProfile> uploadPhoto(Uint8List bytes, String filename) {
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)});
    return _client.call((dio) => dio.post('/users/me/profile-image', data: form), _profile);
  }

  // ---- Achievements ----

  Future<List<Achievement>> achievements() => _client.call(
        (dio) => dio.get('/users/me/achievements'),
        (d) => (d as List).map((e) => Achievement.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Future<void> saveAchievement(String? id, Map<String, dynamic> body) => _client.call(
        (dio) => id == null ? dio.post('/users/me/achievements', data: body) : dio.put('/users/me/achievements/$id', data: body),
        (_) {},
      );

  Future<void> deleteAchievement(String id) =>
      _client.call((dio) => dio.delete('/users/me/achievements/$id'), (_) {});

  // ---- Performance log ----

  Future<List<PerformanceLog>> performanceLogs() => _client.call(
        (dio) => dio.get('/users/me/performance-logs'),
        (d) => (d as List).map((e) => PerformanceLog.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Future<void> saveLog(String? id, Map<String, dynamic> body) => _client.call(
        (dio) => id == null ? dio.post('/users/me/performance-logs', data: body) : dio.put('/users/me/performance-logs/$id', data: body),
        (_) {},
      );

  Future<void> deleteLog(String id) =>
      _client.call((dio) => dio.delete('/users/me/performance-logs/$id'), (_) {});
}

final selfProfileApiProvider = Provider((ref) => SelfProfileApi(ref.watch(dioClientProvider)));
final selfProfileProvider = FutureProvider.autoDispose((ref) => ref.watch(selfProfileApiProvider).get());
final studentProfileProvider = FutureProvider.autoDispose.family<StudentProfile, String>(
    (ref, membershipId) => ref.watch(selfProfileApiProvider).forStudent(membershipId));
final achievementsProvider = FutureProvider.autoDispose((ref) => ref.watch(selfProfileApiProvider).achievements());
final performanceLogsProvider = FutureProvider.autoDispose((ref) => ref.watch(selfProfileApiProvider).performanceLogs());
