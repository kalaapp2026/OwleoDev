import 'package:nest_fe/core/network/dio_client.dart';

/// A Guest's request to become an Artist (PRD 7.4 addendum), reviewed by Super Admin.
class ArtistApplication {
  final String id;
  final String userId;
  final String? username;
  final String? fullName;
  final String status;
  // Nullable: the apply() response is built in the same transaction as the insert, before
  // Hibernate's @CreationTimestamp value has been flushed - it's only reliably populated once
  // re-fetched later (e.g. by listPending()).
  final String? createdAt;

  const ArtistApplication({
    required this.id,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.status,
    required this.createdAt,
  });

  factory ArtistApplication.fromJson(Map<String, dynamic> json) => ArtistApplication(
        id: json['id'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String?,
        fullName: json['fullName'] as String?,
        status: json['status'] as String,
        createdAt: json['createdAt'] as String?,
      );
}

class ArtistApplicationApi {
  ArtistApplicationApi(this._client);
  final DioClient _client;

  /// Any authenticated Guest applies for themselves.
  Future<ArtistApplication> apply() {
    return _client.call(
      (dio) => dio.post('/artist-applications'),
      (data) => ArtistApplication.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Super Admin only.
  Future<List<ArtistApplication>> listPending() {
    return _client.call(
      (dio) => dio.get('/admin/artist-applications'),
      (data) => (data as List).map((e) => ArtistApplication.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<ArtistApplication> approve(String id) {
    return _client.call(
      (dio) => dio.post('/admin/artist-applications/$id/approve'),
      (data) => ArtistApplication.fromJson(data as Map<String, dynamic>),
    );
  }

  Future<ArtistApplication> reject(String id) {
    return _client.call(
      (dio) => dio.post('/admin/artist-applications/$id/reject'),
      (data) => ArtistApplication.fromJson(data as Map<String, dynamic>),
    );
  }
}
