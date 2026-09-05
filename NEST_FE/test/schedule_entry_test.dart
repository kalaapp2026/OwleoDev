import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';
import 'package:nest_fe/features/scheduling/data/schedule_entry.dart';

Map<String, dynamic> entryJson({
  String status = 'SCHEDULED',
  String date = '2026-09-07',
  List<Map<String, dynamic>> instructors = const [],
  List<Map<String, dynamic>> regulars = const [],
  String? reason,
  String? movedTo,
  String? movedFrom,
  String batchType = 'REGULAR',
}) =>
    {
      'classInstanceId': 'ci1',
      'date': date,
      'startTime': '16:00:00',
      'endTime': '17:00:00',
      'status': status,
      'batchId': 'b1',
      'batchName': 'Batch A',
      'batchType': batchType,
      'courseId': 'c1',
      'courseName': 'Guitar Beginner',
      'courseCategory': 'MUSIC',
      'courseIconKey': 'guitar',
      'instructors': instructors,
      'regularInstructors': regulars,
      'reason': reason,
      'movedTo': movedTo,
      'movedFrom': movedFrom,
    };

void main() {
  group('status vocabulary', () {
    test('round-trips every wire value', () {
      for (final status in ScheduleEntryStatus.values) {
        expect(ScheduleEntryStatus.fromWire(status.wire), status);
      }
    });

    test('an unknown status degrades to scheduled rather than throwing', () {
      // A newer server growing a status must not make the whole feed unrenderable.
      expect(ScheduleEntryStatus.fromWire('TELEPORTED'), ScheduleEntryStatus.scheduled);
      expect(ScheduleEntryStatus.fromWire(null), ScheduleEntryStatus.scheduled);
    });

    test('only the vacated slot is a ghost', () {
      for (final status in ScheduleEntryStatus.values) {
        expect(status.isGhost, status == ScheduleEntryStatus.movedOut,
            reason: '${status.name} ghost flag is wrong');
      }
    });

    test('cancelled and vacated slots are not classes that meet', () {
      // Drives the calendar dots: neither should add a dot for a class taking place.
      expect(ScheduleEntryStatus.cancelled.meets, isFalse);
      expect(ScheduleEntryStatus.movedOut.meets, isFalse);
      expect(ScheduleEntryStatus.scheduled.meets, isTrue);
      expect(ScheduleEntryStatus.swapped.meets, isTrue);
      expect(ScheduleEntryStatus.movedIn.meets, isTrue);
      expect(ScheduleEntryStatus.held.meets, isTrue);
    });

    test('"changed" covers both halves of a move plus a substitution', () {
      expect(ScheduleEntryStatus.movedIn.isChanged, isTrue);
      expect(ScheduleEntryStatus.movedOut.isChanged, isTrue);
      expect(ScheduleEntryStatus.swapped.isChanged, isTrue);
      // Cancelled has its own filter chip, so it deliberately isn't folded in here.
      expect(ScheduleEntryStatus.cancelled.isChanged, isFalse);
      expect(ScheduleEntryStatus.scheduled.isChanged, isFalse);
    });

    test('every status resolves a distinct-enough colour pair', () {
      const palette = AppPalette.dark;
      for (final status in ScheduleEntryStatus.values) {
        expect(status.color(palette), isNotNull);
        expect(status.softColor(palette), isNotNull);
      }
      // Cancelled must not share the ordinary scheduled accent, or the feed's most important
      // distinction would vanish.
      expect(ScheduleEntryStatus.cancelled.color(palette),
          isNot(ScheduleEntryStatus.scheduled.color(palette)));
    });
  });

  group('available actions', () {
    test('a scheduled class offers the full set of changes', () {
      final entry = ScheduleEntry.fromJson(entryJson());
      expect(entry.availableActions, containsAll([
        ScheduleAction.reschedule,
        ScheduleAction.swap,
        ScheduleAction.recurring,
        ScheduleAction.cancel,
      ]));
    });

    test('a cancelled class only offers restore', () {
      final entry = ScheduleEntry.fromJson(entryJson(status: 'CANCELLED'));
      expect(entry.availableActions, contains(ScheduleAction.restore));
      expect(entry.availableActions, isNot(contains(ScheduleAction.cancel)));
      expect(entry.availableActions, isNot(contains(ScheduleAction.reschedule)));
    });

    test('a vacated slot only offers undo - it is not a class', () {
      final entry = ScheduleEntry.fromJson(entryJson(status: 'MOVED_OUT'));
      expect(entry.availableActions,
          [ScheduleAction.undoReschedule, ScheduleAction.viewBatch]);
    });

    test('a swapped class offers undo-swap instead of swap', () {
      final entry = ScheduleEntry.fromJson(entryJson(status: 'SWAPPED'));
      expect(entry.availableActions, contains(ScheduleAction.undoSwap));
      expect(entry.availableActions, isNot(contains(ScheduleAction.swap)));
    });

    test('a moved-in class cannot start another recurring change', () {
      // Changing the pattern from a date that was itself reached by a one-off move would be
      // ambiguous about which date the change runs from.
      final entry = ScheduleEntry.fromJson(entryJson(status: 'MOVED_IN'));
      expect(entry.availableActions, contains(ScheduleAction.undoReschedule));
      expect(entry.availableActions, isNot(contains(ScheduleAction.recurring)));
    });

    test('a held class is history and offers nothing destructive', () {
      final entry = ScheduleEntry.fromJson(entryJson(status: 'HELD'));
      expect(entry.availableActions, [ScheduleAction.viewBatch]);
    });

    test('every status yields at least one action, so no row is a dead end', () {
      for (final status in ScheduleEntryStatus.values) {
        final entry = ScheduleEntry.fromJson(entryJson(status: status.wire));
        expect(entry.availableActions, isNotEmpty, reason: '${status.name} has no actions');
      }
    });
  });

  group('deserialisation', () {
    test('reads the joined batch and course fields', () {
      final entry = ScheduleEntry.fromJson(entryJson());
      expect(entry.batchName, 'Batch A');
      expect(entry.courseName, 'Guitar Beginner');
      expect(entry.courseCategory, CourseCategory.music);
      expect(entry.courseIconKey, 'guitar');
      expect(entry.batchType, BatchType.regular);
      expect(entry.isTemporary, isFalse);
    });

    test('formats the time range from wire times carrying seconds', () {
      expect(ScheduleEntry.fromJson(entryJson()).timeRange, '4:00 PM-5:00 PM');
    });

    test('names both the substitute and the usual instructor on a swap', () {
      final entry = ScheduleEntry.fromJson(entryJson(
        status: 'SWAPPED',
        instructors: [
          {'membershipId': 'm2', 'name': 'Karthik Suresh'}
        ],
        regulars: [
          {'membershipId': 'm1', 'name': 'Meera Krishnan'}
        ],
      ));
      expect(entry.instructorSummary, 'Karthik Suresh');
      expect(entry.regularInstructorSummary, 'Meera Krishnan');
    });

    test('a class with no instructor says so rather than rendering blank', () {
      expect(ScheduleEntry.fromJson(entryJson()).instructorSummary, 'No instructor set');
    });

    test('carries the reschedule partner dates', () {
      final movedIn = ScheduleEntry.fromJson(
          entryJson(status: 'MOVED_IN', movedFrom: '2026-09-05', reason: 'Public holiday'));
      expect(movedIn.movedFrom, DateTime(2026, 9, 5));
      expect(movedIn.reason, 'Public holiday');

      final movedOut =
          ScheduleEntry.fromJson(entryJson(status: 'MOVED_OUT', movedTo: '2026-09-09'));
      expect(movedOut.movedTo, DateTime(2026, 9, 9));
      expect(movedOut.movedFrom, isNull);
    });

    test('an unknown course category degrades to the neutral treatment', () {
      final json = entryJson()..['courseCategory'] = 'ASTROPHYSICS';
      expect(ScheduleEntry.fromJson(json).courseCategory, CourseCategory.unknown);
    });

    test('missing instructor lists degrade to empty rather than throwing', () {
      final json = entryJson()
        ..remove('instructors')
        ..remove('regularInstructors');
      final entry = ScheduleEntry.fromJson(json);
      expect(entry.instructors, isEmpty);
      expect(entry.regularInstructors, isEmpty);
    });

    test('a temporary batch is flagged', () {
      expect(ScheduleEntry.fromJson(entryJson(batchType: 'TEMPORARY')).isTemporary, isTrue);
    });
  });

  group('change reasons', () {
    test('offers Other last so the presets are tried first', () {
      expect(scheduleChangeReasons.last, 'Other');
      expect(scheduleChangeReasons, hasLength(6));
    });
  });
}
