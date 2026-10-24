import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/core/error/api_exception.dart';

void main() {
  group('ApiException message', () {
    test('a rejected form shows the first real reason, not the generic line', () {
      final e = ApiException.fromJson({
        'status': 400,
        'code': 'VALIDATION_FAILED',
        'message': 'Request failed validation',
        'validationErrors': [
          {'field': 'phone', 'message': 'Enter a valid phone number, with its country code (for example +91 9876543210).'},
        ],
      });
      expect(e.message, 'Enter a valid phone number, with its country code (for example +91 9876543210).');
      expect(e.isValidation, isTrue);
      expect(e.fieldError('phone'), isNotNull);
    });

    test('says how many other problems there are', () {
      final e = ApiException.fromJson({
        'code': 'VALIDATION_FAILED',
        'message': 'Request failed validation',
        'validationErrors': [
          {'field': 'username', 'message': 'A username is 3 to 30 characters.'},
          {'field': 'phone', 'message': 'Enter a valid phone number.'},
          {'field': 'email', 'message': 'That email address looks incomplete.'},
        ],
      });
      expect(e.message, 'A username is 3 to 30 characters. (and 2 more to fix)');
      expect(e.fieldError('email'), 'That email address looks incomplete.');
    });

    test('other errors keep the server message', () {
      final e = ApiException.fromJson({'status': 409, 'code': 'CONFLICT', 'message': 'Username already taken'});
      expect(e.message, 'Username already taken');
      expect(e.validationErrors, isNull);
    });

    test('validation errors with nothing readable fall back to the server message', () {
      final e = ApiException.fromJson({
        'code': 'VALIDATION_FAILED',
        'message': 'Request failed validation',
        'validationErrors': <Map<String, String>>[],
      });
      expect(e.message, 'Request failed validation');
    });

    test('an empty body still says something', () {
      expect(ApiException.fromJson({}).message, 'Something went wrong');
    });
  });
}
