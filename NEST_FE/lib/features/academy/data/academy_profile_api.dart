import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:nest_fe/core/network/dio_client.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';

class AcademyProfileApi {
  AcademyProfileApi(this._client);
  final DioClient _client;

  Future<AcademyProfile> getProfile() {
    return _client.call(
      (dio) => dio.get('/academies/me'),
      (data) => AcademyProfile.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<AcademyProfile> updateProfile({
    String? tagline,
    String? description,
    String? establishedBy,
    String? ownerName,
    String? additionalInfo,
    String? address,
    String? contactNumber,
    String? email,
    String? instagramUrl,
    String? xUrl,
    String? facebookUrl,
    String? youtubeUrl,
  }) {
    return _client.call(
      (dio) => dio.put('/academies/me', data: {
        'tagline': tagline,
        'description': description,
        'establishedBy': establishedBy,
        'ownerName': ownerName,
        'additionalInfo': additionalInfo,
        'address': address,
        'contactNumber': contactNumber,
        'email': email,
        'instagramUrl': instagramUrl,
        'xUrl': xUrl,
        'facebookUrl': facebookUrl,
        'youtubeUrl': youtubeUrl,
      }),
      (data) => AcademyProfile.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<AcademyProfile> uploadLogo(Uint8List bytes, String filename) {
    final formData = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)});
    return _client.call(
      (dio) => dio.post('/academies/me/logo', data: formData),
      (data) => AcademyProfile.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<AcademyHighlight> addHighlight({required String title, String? description, Set<String> trainerMembershipIds = const {}}) {
    return _client.call(
      (dio) => dio.post('/academies/me/highlights', data: {
        'title': title,
        'description': description,
        'trainerMembershipIds': trainerMembershipIds.toList(),
      }),
      (data) => AcademyHighlight.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<AcademyHighlight> updateHighlight({
    required String highlightId,
    required String title,
    String? description,
    Set<String> trainerMembershipIds = const {},
  }) {
    return _client.call(
      (dio) => dio.put('/academies/me/highlights/$highlightId', data: {
        'title': title,
        'description': description,
        'trainerMembershipIds': trainerMembershipIds.toList(),
      }),
      (data) => AcademyHighlight.fromJson(data as Map<String, dynamic>),
    );
  }

  /// A highlight can carry several photos - each call adds one more to its carousel.
  Future<AcademyHighlight> addHighlightImage(String highlightId, Uint8List bytes, String filename) {
    final formData = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)});
    return _client.call(
      (dio) => dio.post('/academies/me/highlights/$highlightId/images', data: formData),
      (data) => AcademyHighlight.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteHighlightImage(String highlightId, String imageId) {
    return _client.callVoid((dio) => dio.delete('/academies/me/highlights/$highlightId/images/$imageId'));
  }

  Future<void> deleteHighlight(String highlightId) {
    return _client.callVoid((dio) => dio.delete('/academies/me/highlights/$highlightId'));
  }

  Future<List<TrainerCandidate>> listTrainerCandidates() {
    return _client.call(
      (dio) => dio.get('/academies/me/trainer-candidates'),
      (data) => (data as List).map((e) => TrainerCandidate.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<FeaturedTrainer> addFeaturedTrainer(String trainerMembershipId) {
    return _client.call(
      (dio) => dio.post('/academies/me/featured-trainers', data: {'trainerMembershipId': trainerMembershipId}),
      (data) => FeaturedTrainer.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteFeaturedTrainer(String featuredTrainerId) {
    return _client.callVoid((dio) => dio.delete('/academies/me/featured-trainers/$featuredTrainerId'));
  }

  Future<AcademyBranchInfo> addBranch({required String name, String? address}) {
    return _client.call(
      (dio) => dio.post('/academies/me/branches', data: {'name': name, 'address': address}),
      (data) => AcademyBranchInfo.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<void> deleteBranch(String branchId) {
    return _client.callVoid((dio) => dio.delete('/academies/me/branches/$branchId'));
  }
}
