import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/core/design/time_picker_sheet.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';

void main() {
  group('ClockTime parsing', () {
    test('accepts HH:mm and HH:mm:ss', () {
      // The schedule API returns seconds; the batch form writes without them. Both have to land
      // on the same value or editing a batch would appear to change its time.
      expect(ClockTime.tryParse('16:00'), const ClockTime(16, 0));
      expect(ClockTime.tryParse('16:00:00'), const ClockTime(16, 0));
      expect(ClockTime.tryParse('09:30:45'), const ClockTime(9, 30));
    });

    test('rejects malformed and out-of-range values rather than guessing', () {
      expect(ClockTime.tryParse(null), isNull);
      expect(ClockTime.tryParse(''), isNull);
      expect(ClockTime.tryParse('1600'), isNull);
      expect(ClockTime.tryParse('24:00'), isNull);
      expect(ClockTime.tryParse('12:60'), isNull);
      expect(ClockTime.tryParse('ab:cd'), isNull);
    });

    test('round-trips through the wire format', () {
      for (final raw in ['00:00', '09:05', '12:00', '13:45', '23:59']) {
        expect(ClockTime.tryParse(raw)!.wire, raw);
      }
    });
  });

  group('ClockTime display', () {
    test('renders 12-hour with midnight and noon as 12, not 0', () {
      expect(const ClockTime(0, 0).label, '12:00 AM');
      expect(const ClockTime(12, 0).label, '12:00 PM');
      expect(const ClockTime(16, 5).label, '4:05 PM');
      expect(const ClockTime(9, 30).label, '9:30 AM');
    });

    test('hour12 and isPm agree with the label', () {
      expect(const ClockTime(0, 0).hour12, 12);
      expect(const ClockTime(0, 0).isPm, isFalse);
      expect(const ClockTime(12, 0).hour12, 12);
      expect(const ClockTime(12, 0).isPm, isTrue);
      expect(const ClockTime(23, 0).hour12, 11);
    });
  });

  group('ClockTime ordering', () {
    test('compares across the noon boundary', () {
      // The end-time picker's minimum check relies on this; getting it wrong would let a class
      // end before it starts whenever the pair straddled midday.
      expect(const ClockTime(11, 59) < const ClockTime(12, 0), isTrue);
      expect(const ClockTime(12, 0) < const ClockTime(13, 0), isTrue);
      expect(const ClockTime(9, 0) < const ClockTime(9, 1), isTrue);
      expect(const ClockTime(17, 0) > const ClockTime(16, 59), isTrue);
    });

    test('equal times are neither before nor after', () {
      const a = ClockTime(10, 30);
      const b = ClockTime(10, 30);
      expect(a < b, isFalse);
      expect(a > b, isFalse);
      expect(a <= b, isTrue);
      expect(a >= b, isTrue);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ClockTime.fromParts', () {
    test('maps 12 AM to midnight and 12 PM to noon', () {
      expect(ClockTime.fromParts(hour12: 12, minute: 0, pm: false), const ClockTime(0, 0));
      expect(ClockTime.fromParts(hour12: 12, minute: 0, pm: true), const ClockTime(12, 0));
    });

    test('maps afternoon hours past 12', () {
      expect(ClockTime.fromParts(hour12: 4, minute: 30, pm: true), const ClockTime(16, 30));
      expect(ClockTime.fromParts(hour12: 4, minute: 30, pm: false), const ClockTime(4, 30));
    });
  });

  group('weekday formatting', () {
    test('lists days in week order regardless of selection order', () {
      // The day picker is a set, so insertion order is whatever the admin tapped. Showing
      // "Fri, Mon, Wed" would read as wrong even though the data is right.
      expect(formatDays({Weekday.friday, Weekday.monday, Weekday.wednesday}),
          'Mon, Wed, Fri');
    });

    test('collapses a full week and names the empty case', () {
      expect(formatDays(Weekday.values.toSet()), 'Every day');
      expect(formatDays(const <Weekday>{}), 'No days set');
    });

    test('maps to and from the wire names', () {
      for (final day in Weekday.values) {
        expect(Weekday.fromWire(day.wire), day);
      }
    });

    test('Weekday.of agrees with DateTime.weekday', () {
      // 1 Sep 2026 is a Tuesday.
      expect(Weekday.of(DateTime(2026, 9, 1)), Weekday.tuesday);
      expect(Weekday.of(DateTime(2026, 9, 6)), Weekday.sunday);
    });
  });

  group('batch time formatting', () {
    test('formats wire times with and without seconds', () {
      expect(formatTimeOfDay('16:00'), '4:00 PM');
      expect(formatTimeOfDay('16:00:00'), '4:00 PM');
      expect(formatTimeOfDay('09:05'), '9:05 AM');
      expect(formatTimeOfDay('00:30'), '12:30 AM');
    });

    test('returns empty rather than a placeholder for an absent time', () {
      expect(formatTimeOfDay(null), '');
      expect(formatTimeOfDay(''), '');
    });
  });

  group('Batch deserialisation', () {
    Map<String, dynamic> json({
      String type = 'REGULAR',
      String? start,
      String? end,
      List<Map<String, dynamic>> trainers = const [],
      int studentCount = 0,
    }) =>
        {
          'id': 'b1',
          'courseId': 'c1',
          'name': 'Batch A',
          'description': null,
          'batchType': type,
          'trainerMembershipId': null,
          'trainerName': null,
          'status': 'ACTIVE',
          'startDate': start,
          'endDate': end,
          'trainers': trainers,
          'studentCount': studentCount,
        };

    test('reads trainers and roster size', () {
      final batch = Batch.fromJson(json(
        trainers: [
          {'membershipId': 'm1', 'name': 'Meera Krishnan'},
          {'membershipId': 'm2', 'name': 'Karthik Suresh'},
        ],
        studentCount: 4,
      ));

      expect(batch.trainers.map((t) => t.name),
          ['Meera Krishnan', 'Karthik Suresh']);
      expect(batch.trainerSummary, 'Meera Krishnan, Karthik Suresh');
      expect(batch.studentCount, 4);
    });

    test('a batch with no trainers says so rather than rendering blank', () {
      expect(Batch.fromJson(json()).trainerSummary, 'No instructor set');
    });

    test('summarises a temporary batch as a range and a regular one as open-ended', () {
      expect(
        Batch.fromJson(json(type: 'TEMPORARY', start: '2026-09-01', end: '2026-10-24'))
            .dateRangeSummary,
        '1 Sep 2026 - 24 Oct 2026',
      );
      expect(
        Batch.fromJson(json(start: '2026-09-01')).dateRangeSummary,
        'From 1 Sep 2026',
      );
    });

    test('a batch predating the date columns has no range rather than a bogus one', () {
      expect(Batch.fromJson(json()).dateRangeSummary, isNull);
    });

    test('missing trainers/studentCount degrade to empty rather than throwing', () {
      // An older server build simply won't send these; the list screen must still render.
      final batch = Batch.fromJson({
        'id': 'b1',
        'courseId': 'c1',
        'name': 'Batch A',
        'batchType': 'REGULAR',
        'status': 'ACTIVE',
      });
      expect(batch.trainers, isEmpty);
      expect(batch.studentCount, 0);
      expect(batch.isTemporary, isFalse);
    });
  });
}
