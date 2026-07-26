import 'package:nest_fe/core/network/dio_client.dart';

/// One people-search result - just enough to show a face and a name, never PII.
class PersonResult {
  final String id;
  final String username;
  final String fullName;
  final String? profileImageUrl;

  PersonResult({required this.id, required this.username, required this.fullName, required this.profileImageUrl});

  factory PersonResult.fromJson(Map<String, dynamic> json) => PersonResult(
        id: json['id'] as String,
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        profileImageUrl: json['profileImageUrl'] as String?,
      );
}

class PeopleSearchApi {
  PeopleSearchApi(this._client);
  final DioClient _client;

  Future<List<PersonResult>> search(String query) {
    return _client.call(
      (dio) => dio.get('/users/search', queryParameters: {'q': query}),
      (data) => (data as List).map((e) => PersonResult.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
