import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/features/curriculum/data/material_playlist.dart';
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

/// Every file of one type across every batch this caller can see - the Song, Document and
/// Image libraries, which cut across batches rather than sitting inside one.
final materialLibraryProvider =
    FutureProvider.autoDispose.family<List<StudyMaterial>, StudyMaterialType>((ref, fileType) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(studyMaterialApiProvider).library(fileType);
});

/// The caller's own playlists.
final materialPlaylistsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(studyMaterialApiProvider).playlists();
});

final materialPlaylistProvider =
    FutureProvider.autoDispose.family<MaterialPlaylist, String>((ref, playlistId) {
  return ref.watch(studyMaterialApiProvider).playlist(playlistId);
});

/// Saved player state for one track. Falls back to defaults server-side, so this never 404s.
final playbackSettingsProvider =
    FutureProvider.autoDispose.family<PlaybackSettings, String>((ref, materialId) {
  return ref.watch(studyMaterialApiProvider).playbackSettings(materialId);
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
    StudyMaterialVisibility visibility = StudyMaterialVisibility.all,
    Set<String> studentIds = const {},
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
          'visibility': visibility.wire,
          // Repeated form fields, which is how Spring binds a Set<UUID> from a multipart
          // request. Omitted entirely when empty so the server sees absent, not blank.
          if (visibility == StudyMaterialVisibility.selected && studentIds.isNotEmpty)
            'studentIds': studentIds.toList(),
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
    StudyMaterialVisibility visibility = StudyMaterialVisibility.all,
    Set<String> studentIds = const {},
  }) {
    return _client.call(
      (dio) => dio.put('/study-materials/$materialId', data: {
        'title': title,
        'description': description,
        'permission': permission.wire,
        'visibility': visibility.wire,
        'studentIds': studentIds.toList(),
      }),
      (data) => StudyMaterial.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<List<StudyMaterial>> library(StudyMaterialType fileType) {
    return _client.call(
      (dio) => dio.get('/study-materials/library',
          queryParameters: {'fileType': fileType.wire}),
      (data) => (data as List)
          .map((e) => StudyMaterial.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ---- playlists ----

  Future<List<MaterialPlaylist>> playlists() {
    return _client.call(
      (dio) => dio.get('/material-playlists'),
      (data) => (data as List)
          .map((e) => MaterialPlaylist.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<MaterialPlaylist> playlist(String playlistId) {
    return _client.call(
      (dio) => dio.get('/material-playlists/$playlistId'),
      (data) => MaterialPlaylist.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<MaterialPlaylist> createPlaylist(String name) {
    return _client.call(
      (dio) => dio.post('/material-playlists', data: {'name': name}),
      (data) => MaterialPlaylist.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<MaterialPlaylist> renamePlaylist(String playlistId, String name) {
    return _client.call(
      (dio) => dio.put('/material-playlists/$playlistId', data: {'name': name}),
      (data) => MaterialPlaylist.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deletePlaylist(String playlistId) {
    return _client.callVoid((dio) => dio.delete('/material-playlists/$playlistId'));
  }

  Future<MaterialPlaylist> addToPlaylist(String playlistId, List<String> materialIds) {
    return _client.call(
      (dio) => dio.post('/material-playlists/$playlistId/entries',
          data: {'materialIds': materialIds}),
      (data) => MaterialPlaylist.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Addressed by entry id, not material id - the same song can appear twice.
  Future<MaterialPlaylist> removeFromPlaylist(String playlistId, String entryId) {
    return _client.call(
      (dio) => dio.delete('/material-playlists/$playlistId/entries/$entryId'),
      (data) => MaterialPlaylist.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<MaterialPlaylist> duplicateEntry(String playlistId, String entryId) {
    return _client.call(
      (dio) => dio.post('/material-playlists/$playlistId/entries/$entryId/duplicate'),
      (data) => MaterialPlaylist.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Sends the whole running order rather than a from/to pair, so a drag that moves a row
  /// several places cannot be reconciled into a different order than the one on screen.
  Future<MaterialPlaylist> reorderPlaylist(String playlistId, List<String> entryIds) {
    return _client.call(
      (dio) => dio.put('/material-playlists/$playlistId/order',
          data: {'entryIds': entryIds}),
      (data) => MaterialPlaylist.fromJson(data as Map<String, dynamic>),
    );
  }

  // ---- playback settings ----

  Future<PlaybackSettings> playbackSettings(String materialId) {
    return _client.call(
      (dio) => dio.get('/study-materials/$materialId/playback'),
      (data) => PlaybackSettings.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<PlaybackSettings> savePlaybackSettings(
      String materialId, PlaybackSettings settings) {
    return _client.call(
      (dio) => dio.put('/study-materials/$materialId/playback', data: settings.toJson()),
      (data) => PlaybackSettings.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> delete(String materialId) {
    return _client.callVoid((dio) => dio.delete('/study-materials/$materialId'));
  }
}
