import 'package:flutter/widgets.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/time_picker_sheet.dart';
import 'package:nest_fe/features/enrolment/data/batch.dart';

/// How a schedule row reads to the person looking at it.
///
/// A presentation vocabulary, not the stored status: one rescheduled class is a single stored
/// pair but two rows here, and a substitution is a scheduled class that happens to carry a
/// stand-in rather than a status of its own.
enum ScheduleEntryStatus {
  scheduled('SCHEDULED', 'Scheduled'),
  swapped('SWAPPED', 'Substitute'),
  movedIn('MOVED_IN', 'Rescheduled'),
  movedOut('MOVED_OUT', 'Moved'),
  cancelled('CANCELLED', 'Cancelled'),
  held('HELD', 'Held');

  const ScheduleEntryStatus(this.wire, this.label);

  final String wire;
  final String label;

  static ScheduleEntryStatus fromWire(String? value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => ScheduleEntryStatus.scheduled);

  /// The row's accent. Cancelled is the only one that borrows a semantic colour, because it is
  /// the only status that means something went wrong.
  Color color(AppPalette p) => switch (this) {
        ScheduleEntryStatus.scheduled => p.primary,
        ScheduleEntryStatus.swapped => p.violet,
        ScheduleEntryStatus.movedIn => p.gold,
        ScheduleEntryStatus.movedOut => p.textFaint,
        ScheduleEntryStatus.cancelled => p.notPaid,
        ScheduleEntryStatus.held => p.paidManual,
      };

  Color softColor(AppPalette p) => switch (this) {
        ScheduleEntryStatus.scheduled => p.primarySoft,
        ScheduleEntryStatus.swapped => p.violetSoft,
        ScheduleEntryStatus.movedIn => p.goldSoft,
        ScheduleEntryStatus.movedOut => p.surfaceHigh,
        ScheduleEntryStatus.cancelled => p.notPaidSoft,
        ScheduleEntryStatus.held => p.paidManualSoft,
      };

  /// The vacated slot is drawn as a dashed outline rather than a filled card - it is a note about
  /// where a class used to be, not a class.
  bool get isGhost => this == ScheduleEntryStatus.movedOut;

  /// Whether the row still represents a class that will actually meet. Drives the calendar dots:
  /// a cancelled or vacated slot marks the day but doesn't add a dot for a class taking place.
  bool get meets =>
      this != ScheduleEntryStatus.cancelled && this != ScheduleEntryStatus.movedOut;

  /// Whether this row counts as "changed" for the feed's filter chip.
  bool get isChanged =>
      this == ScheduleEntryStatus.movedIn ||
      this == ScheduleEntryStatus.movedOut ||
      this == ScheduleEntryStatus.swapped;
}

/// Where a class stands on attendance. Ordered by how much it demands of the reader: an unmarked
/// past class is work outstanding, which is what the Attendance screen is for.
enum AttendanceChip {
  notMarked('Not marked'),
  marked('Marked'),
  upcoming('Upcoming');

  const AttendanceChip(this.label);
  final String label;

  Color color(AppPalette p) => switch (this) {
        AttendanceChip.notMarked => p.gold,
        AttendanceChip.marked => p.paidManual,
        AttendanceChip.upcoming => p.primary,
      };

  Color softColor(AppPalette p) => switch (this) {
        AttendanceChip.notMarked => p.goldSoft,
        AttendanceChip.marked => p.paidManualSoft,
        AttendanceChip.upcoming => p.primarySoft,
      };
}

class SchedulePerson {
  const SchedulePerson({required this.membershipId, required this.name});

  final String membershipId;
  final String name;

  factory SchedulePerson.fromJson(Map<String, dynamic> json) => SchedulePerson(
        membershipId: json['membershipId'] as String,
        name: json['name'] as String? ?? '',
      );
}

/// One dated class, already joined to its batch, course and instructors.
class ScheduleEntry {
  final String classInstanceId;
  final DateTime date;
  final String startTime;
  final String endTime;
  final ScheduleEntryStatus status;

  final String batchId;
  final String batchName;
  final BatchType batchType;

  final String? courseId;
  final String? courseName;
  final CourseCategory courseCategory;
  final String? courseIconKey;

  final List<SchedulePerson> instructors;

  /// Only on a swapped row - who would normally teach it.
  final List<SchedulePerson> regularInstructors;

  final String? reason;
  final DateTime? movedTo;
  final DateTime? movedFrom;

  /// Whether attendance has been taken. The Attendance screen exists to find the classes where
  /// it hasn't, so this is the field that screen is actually organised around.
  final bool attendanceMarked;

  /// Roster size, so the attendance list can show "4 students" before the class is opened.
  final int studentCount;

  const ScheduleEntry({
    required this.classInstanceId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.batchId,
    required this.batchName,
    required this.batchType,
    required this.courseId,
    required this.courseName,
    required this.courseCategory,
    required this.courseIconKey,
    required this.instructors,
    required this.regularInstructors,
    required this.reason,
    required this.movedTo,
    required this.movedFrom,
    this.attendanceMarked = false,
    this.studentCount = 0,
  });

  bool get isTemporary => batchType == BatchType.temporary;

  String get timeRange =>
      '${formatTimeOfDay(startTime)}-${formatTimeOfDay(endTime)}';

  String get instructorSummary =>
      instructors.isEmpty ? 'No instructor set' : instructors.map((p) => p.name).join(', ');

  String get regularInstructorSummary => regularInstructors.isEmpty
      ? 'no one in particular'
      : regularInstructors.map((p) => p.name).join(', ');

  /// The start time as a comparable value, for sorting within a day.
  ClockTime? get start => ClockTime.tryParse(startTime);

  /// Whether attendance can be taken for this session: it has to be a class that actually meets,
  /// and it can't be in the future. Marking a class that hasn't happened would be a guess.
  bool canMarkAttendance(DateTime today) {
    if (!status.meets) return false;
    final day = DateTime(date.year, date.month, date.day);
    final now = DateTime(today.year, today.month, today.day);
    return !day.isAfter(now);
  }

  /// The Attendance screen's chip. Three states, in the order they matter to someone hunting for
  /// work they haven't done: not marked (act on this), marked (done), upcoming (not yet).
  AttendanceChip attendanceChip(DateTime today) {
    if (!canMarkAttendance(today)) return AttendanceChip.upcoming;
    return attendanceMarked ? AttendanceChip.marked : AttendanceChip.notMarked;
  }

  /// Which single-session actions apply. Derived from status rather than stored, because what you
  /// can do to a class follows entirely from what has already been done to it.
  List<ScheduleAction> get availableActions => switch (status) {
        ScheduleEntryStatus.scheduled => const [
            ScheduleAction.reschedule,
            ScheduleAction.swap,
            ScheduleAction.recurring,
            ScheduleAction.cancel,
            ScheduleAction.viewBatch,
          ],
        ScheduleEntryStatus.swapped => const [
            ScheduleAction.reschedule,
            ScheduleAction.undoSwap,
            ScheduleAction.recurring,
            ScheduleAction.cancel,
            ScheduleAction.viewBatch,
          ],
        ScheduleEntryStatus.movedIn => const [
            ScheduleAction.reschedule,
            ScheduleAction.undoReschedule,
            ScheduleAction.cancel,
            ScheduleAction.viewBatch,
          ],
        // The vacated slot isn't a class, so the only meaningful move is putting it back.
        ScheduleEntryStatus.movedOut => const [
            ScheduleAction.undoReschedule,
            ScheduleAction.viewBatch,
          ],
        ScheduleEntryStatus.cancelled => const [
            ScheduleAction.restore,
            ScheduleAction.viewBatch,
          ],
        // A class that already happened is history; changing it would rewrite attendance.
        ScheduleEntryStatus.held => const [ScheduleAction.viewBatch],
      };

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) => ScheduleEntry(
        classInstanceId: json['classInstanceId'] as String,
        date: DateTime.parse(json['date'] as String),
        startTime: json['startTime'] as String,
        endTime: json['endTime'] as String,
        status: ScheduleEntryStatus.fromWire(json['status'] as String?),
        batchId: json['batchId'] as String,
        batchName: json['batchName'] as String? ?? '',
        batchType: BatchType.fromWire(json['batchType'] as String?),
        courseId: json['courseId'] as String?,
        courseName: json['courseName'] as String?,
        courseCategory: CourseCategory.fromWire(json['courseCategory'] as String?),
        courseIconKey: json['courseIconKey'] as String?,
        instructors: ((json['instructors'] as List?) ?? const [])
            .map((p) => SchedulePerson.fromJson(p as Map<String, dynamic>))
            .toList(),
        regularInstructors: ((json['regularInstructors'] as List?) ?? const [])
            .map((p) => SchedulePerson.fromJson(p as Map<String, dynamic>))
            .toList(),
        reason: json['reason'] as String?,
        movedTo: _date(json['movedTo'] as String?),
        movedFrom: _date(json['movedFrom'] as String?),
        attendanceMarked: json['attendanceMarked'] as bool? ?? false,
        studentCount: json['studentCount'] as int? ?? 0,
      );

  static DateTime? _date(String? iso) =>
      (iso == null || iso.isEmpty) ? null : DateTime.tryParse(iso);
}

/// What can be done to one session.
enum ScheduleAction {
  reschedule('Reschedule this class'),
  swap('Swap instructor'),
  recurring('Change schedule from here'),
  cancel('Cancel this class', danger: true),
  restore('Restore this class'),
  undoSwap('Undo substitution'),
  undoReschedule('Undo reschedule'),
  viewBatch('View batch');

  const ScheduleAction(this.label, {this.danger = false});

  final String label;
  final bool danger;
}

/// The reasons offered when changing a session. Free text is still possible via "Other" - these
/// exist so the common cases are one tap rather than a sentence typed on a phone.
const scheduleChangeReasons = [
  'Instructor unavailable',
  'Public holiday',
  'Venue unavailable',
  'Weather / emergency',
  'Student request',
  'Other',
];
