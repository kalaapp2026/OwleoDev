import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/enrolment/presentation/widgets/course_change_section.dart';

void main() {
  group('firstOfNextMonth', () {
    test('is the 1st of the following month', () {
      expect(firstOfNextMonth(DateTime(2026, 10, 30)), DateTime(2026, 11, 1));
      expect(firstOfNextMonth(DateTime(2026, 10, 1)), DateTime(2026, 11, 1));
    });

    test('rolls over the year end', () {
      expect(firstOfNextMonth(DateTime(2026, 12, 20)), DateTime(2027, 1, 1));
    });
  });

  group('CourseChange', () {
    test('reads the courses, the date and the batches it will place the student in', () {
      final change = CourseChange.fromJson({
        'id': 'c1',
        'membershipId': 'm1',
        'fromCourseId': 'basic',
        'fromCourseName': 'Guitar Basic',
        'toCourseId': 'adv',
        'toCourseName': 'Guitar Advanced',
        'effectiveOn': '2026-11-01',
        'status': 'PENDING',
        'toBatchNames': ['Advanced Sat'],
      });

      expect(change.fromCourseName, 'Guitar Basic');
      expect(change.toCourseName, 'Guitar Advanced');
      expect(change.effectiveOn, DateTime(2026, 11, 1));
      expect(change.toBatchNames, ['Advanced Sat']);
    });

    test('a move with no batch chosen has an empty list, not null', () {
      final change = CourseChange.fromJson({
        'id': 'c1',
        'membershipId': 'm1',
        'fromCourseId': 'basic',
        'toCourseId': 'adv',
        'effectiveOn': '2026-11-01',
      });
      expect(change.toBatchNames, isEmpty);
    });
  });
}
