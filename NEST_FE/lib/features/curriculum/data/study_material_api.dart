import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/curriculum/data/study_material.dart';

final studyMaterialApiProvider =
    Provider((ref) => StudyMaterialApi(ref.watch(dioClientProvider)));

/// Batches this caller can manage material for, with file counts - the home screen.
final materialBatchesProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(studyMaterialApiProvider).batchSummaries();
});

/// One batch's files.
final batchMaterialsProvider =
    FutureProvider.autoDispose.family<List<StudyMaterial>, String>((ref, batchId) {
  return ref.watch(studyMaterialApiProvider).listForBatch(batchId);
});

class StudyMaterialApi {
  StudyMaterialApi(this._client);
  final DioClient _client;

  Future<List<BatchMaterialSummary>> batchSummaries() {
    return _client.call(
      (dio) => dio.get('/study-materials/batches'),
      (data) => (data as List)
          .map((e) => BatchMaterialSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<StudyMaterial>> listForBatch(String batchId) {
    return _client.call(
      (dio) => dio.get('/batches/$batchId/study-materials'),
      (data) => (data as List)
          .map((e) => StudyMaterial.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Reads bytes rather than a file path so the same call works on web and on Android/iOS.
  Future<StudyMaterial> upload({
    required String batchId,
    required Uint8List bytes,
    required String fileName,
    required String title,
    String? description,
    required StudyMaterialPermission permission,
  }) {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    return _client.call(
      (dio) => dio.post(
        '/batches/$batchId/study-materials',
        data: form,
        // Title and permission ride as query params rather than form fields: mixing text parts
        // into a multipart body means the server has to decode them per-part, and Spring binds
        // query params to @RequestParam on a multipart request without any of that.
        queryParameters: {
          'title': title,
          'description': ?description,
          'permission': permission.wire,
        },
      ),
      (data) => StudyMaterial.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<StudyMaterial> update(
    String materialId, {
    required String title,
    String? description,
    required StudyMaterialPermission permission,
  }) {
    return _client.call(
      (dio) => dio.put('/study-materials/$materialId', data: {
        'title': title,
        'description': description,
        'permission': permission.wire,
      }),
      (data) => StudyMaterial.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> delete(String materialId) {
    return _client.callVoid((dio) => dio.delete('/study-materials/$materialId'));
  }
}
