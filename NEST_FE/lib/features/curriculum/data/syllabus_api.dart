import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/features/curriculum/data/syllabus_unit.dart';

class SyllabusApi {
  SyllabusApi(this._client);
  final DioClient _client;

  /// Omit membershipId for the Admin/Trainer management view (everything, any targeting) - pass
  /// it for the scoped read-only view (course-wide material this membership is enrolled for, plus
  /// batch-targeted material for batches they're in or teach).
  Future<List<SyllabusUnit>> listForCourse(String courseId, {String? membershipId}) {
    return _client.call(
      (dio) => dio.get('/courses/$courseId/syllabus-units', queryParameters: membershipId == null ? null : {'membershipId': membershipId}),
      (data) => (data as List).map((e) => SyllabusUnit.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<SyllabusUnit> createUnit({
    required String courseId,
    required Set<String> batchIds,
    required String title,
    String? description,
    int orderIndex = 0,
  }) {
    return _client.call(
      (dio) => dio.post('/syllabus-units', data: {
        'courseId': courseId,
        'batchIds': batchIds.toList(),
        'title': title,
        'description': description,
        'orderIndex': orderIndex,
      }),
      (data) => SyllabusUnit.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<SyllabusUnit> updateUnit({
    required String unitId,
    required Set<String> batchIds,
    required String title,
    String? description,
    int orderIndex = 0,
  }) {
    return _client.call(
      (dio) => dio.put('/syllabus-units/$unitId', data: {
        'batchIds': batchIds.toList(),
        'title': title,
        'description': description,
        'orderIndex': orderIndex,
      }),
      (data) => SyllabusUnit.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteUnit(String unitId) {
    return _client.callVoid((dio) => dio.delete('/syllabus-units/$unitId'));
  }

  /// A unit can carry several PDF/image attachments - each call adds one more. Reads bytes rather
  /// than a file path so it works the same on web and Android/iOS (see ProfileImagePicker).
  Future<MaterialAttachment> addAttachment(String unitId, Uint8List bytes, String filename) {
    final formData = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)});
    return _client.call(
      (dio) => dio.post('/syllabus-units/$unitId/materials', data: formData),
      (data) => MaterialAttachment.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<List<MaterialAttachment>> listAttachments(String unitId) {
    return _client.call(
      (dio) => dio.get('/syllabus-units/$unitId/materials'),
      (data) => (data as List).map((e) => MaterialAttachment.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<void> deleteAttachment(String unitId, String attachmentId) {
    return _client.callVoid((dio) => dio.delete('/syllabus-units/$unitId/materials/$attachmentId'));
  }

  Future<SyllabusUnit> setStatus(String unitId, String status) {
    return _client.call(
      (dio) => dio.patch('/syllabus-units/$unitId/status', queryParameters: {'status': status}),
      (data) => SyllabusUnit.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<List<Track>> listTracks(String unitId) {
    return _client.call(
      (dio) => dio.get('/syllabus-units/$unitId/tracks'),
      (data) => (data as List).map((e) => Track.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// title/streamOnly ride along with the audio file in one multipart call - a Track record with
  /// no file isn't meaningful, unlike a SyllabusUnit's separate metadata-then-attachment flow.
  Future<Track> addTrack({required String unitId, required String title, required bool streamOnly, required Uint8List bytes, required String filename}) {
    final formData = FormData.fromMap({
      'title': title,
      'streamOnly': streamOnly,
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    return _client.call(
      (dio) => dio.post('/syllabus-units/$unitId/tracks', data: formData),
      (data) => Track.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteTrack(String unitId, String trackId) {
    return _client.callVoid((dio) => dio.delete('/syllabus-units/$unitId/tracks/$trackId'));
  }
}
