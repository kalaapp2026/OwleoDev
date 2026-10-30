import 'package:nest_fe/core/format/money.dart';

/// Regular batches run until deactivated; temporary ones exist between two dates for a specific
/// purpose (an annual-day rehearsal) and skip the course's regular fee cycle entirely.
enum BatchType {
  regular('REGULAR', 'Regular'),
  temporary('TEMPORARY', 'Temporary');

  const BatchType(this.wire, this.label);

  final String wire;
  final String label;

  static BatchType fromWire(String? value) =>
      value == 'TEMPORARY' ? BatchType.temporary : BatchType.regular;
}

/// A trainer on a batch, already resolved to a display name by the server.
class BatchTrainer {
  const BatchTrainer({required this.membershipId, required this.name});

  final String membershipId;
  final String name;

  factory BatchTrainer.fromJson(Map<String, dynamic> json) => BatchTrainer(
        membershipId: json['membershipId'] as String,
        name: json['name'] as String? ?? '',
      );
}

/// One course a batch covers.
class BatchCourse {
  const BatchCourse({required this.id, required this.name});

  final String id;
  final String name;

  factory BatchCourse.fromJson(Map<String, dynamic> json) =>
      BatchCourse(id: json['id'] as String, name: json['name'] as String? ?? '');
}

/// The days a batch meets. Wire values are `java.time.DayOfWeek` names.
enum Weekday {
  monday('MONDAY', 'Mon', 'M'),
  tuesday('TUESDAY', 'Tue', 'T'),
  wednesday('WEDNESDAY', 'Wed', 'W'),
  thursday('THURSDAY', 'Thu', 'T'),
  friday('FRIDAY', 'Fri', 'F'),
  saturday('SATURDAY', 'Sat', 'S'),
  sunday('SUNDAY', 'Sun', 'S');

  const Weekday(this.wire, this.short, this.initial);

  final String wire;

  /// "Mon" - used when days are listed as prose.
  final String short;

  /// "M" - the single letter on the day-picker cells. Ambiguous on its own (two Ts, two Ss),
  /// which is why the picker cells also carry the full name as a tooltip.
  final String initial;

  static Weekday fromWire(String value) =>
      values.firstWhere((d) => d.wire == value, orElse: () => Weekday.monday);

  /// Dart's [DateTime.weekday] is 1=Monday..7=Sunday, matching this enum's order.
  static Weekday of(DateTime date) => values[date.weekday - 1];
}

/// "Mon, Wed, Fri" - always in week order regardless of the order they were selected in.
String formatDays(Iterable<Weekday> days) {
  if (days.isEmpty) return 'No days set';
  if (days.length == 7) return 'Every day';
  final sorted = days.toList()..sort((a, b) => a.index.compareTo(b.index));
  return sorted.map((d) => d.short).join(', ');
}

/// "4:00 PM" from a wire "16:00" or "16:00:00".
String formatTimeOfDay(String? time) {
  if (time == null || time.isEmpty) return '';
  final parts = time.split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  final period = hour >= 12 ? 'PM' : 'AM';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $period';
}

class Batch {
  final String id;

  /// The batch's primary course - the first one it was created with. A batch can cover several
  /// ([courses]); anything that asks "is this batch on course X" should use [coversCourse].
  final String courseId;
  final String name;
  final String? description;
  final BatchType batchType;
  final String? trainerMembershipId;
  final String? trainerName;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<BatchTrainer> trainers;
  final int studentCount;

  /// The class time (wire "16:00") and meeting days, from the batch's current schedule; null/empty
  /// until one is set.
  final String? startTime;
  final String? endTime;
  final List<Weekday> days;

  /// The Meet / Zoom / Teams link of an online class; null for an in-person batch.
  final String? meetingLink;

  /// Every course the batch covers, primary first. A batch of Basic + Intermediate + Advanced
  /// learners lists all three; an ordinary batch lists just its one.
  final List<BatchCourse> courses;

  const Batch({
    required this.id,
    required this.courseId,
    required this.name,
    required this.description,
    required this.batchType,
    required this.trainerMembershipId,
    required this.trainerName,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.trainers,
    required this.studentCount,
    this.startTime,
    this.endTime,
    this.days = const [],
    this.meetingLink,
    this.courses = const [],
  });

  /// Ids of every course the batch covers - the primary alone when the server sent no list.
  List<String> get courseIds => courses.isEmpty ? [courseId] : [for (final c in courses) c.id];

  /// Whether this batch belongs under [id] in a course filter or picker.
  bool coversCourse(String? id) => id != null && courseIds.contains(id);

  bool get isMultiCourse => courses.length > 1;

  /// "Guitar Basic, Guitar Advanced" for a multi-course batch; null for an ordinary one.
  String? get courseNamesSummary => isMultiCourse ? courses.map((c) => c.name).join(', ') : null;

  /// "4:00 PM - 5:00 PM", or null while no time is set.
  String? get timeRange => (startTime == null || endTime == null)
      ? null
      : '${formatTimeOfDay(startTime)} - ${formatTimeOfDay(endTime)}';

  bool get isActive => status == 'ACTIVE';
  bool get isTemporary => batchType == BatchType.temporary;

  /// "Meera Krishnan, Karthik Suresh", or a placeholder when the batch has none yet.
  String get trainerSummary =>
      trainers.isEmpty ? 'No instructor set' : trainers.map((t) => t.name).join(', ');

  /// "1 Sep 2026 - 24 Oct 2026" for a temporary batch, "From 1 Sep 2026" for a regular one.
  String? get dateRangeSummary {
    if (startDate == null) return null;
    final from = formatFeeDate(startDate!);
    if (endDate == null) return 'From $from';
    return '$from - ${formatFeeDate(endDate!)}';
  }

  factory Batch.fromJson(Map<String, dynamic> json) => Batch(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        batchType: BatchType.fromWire(json['batchType'] as String?),
        trainerMembershipId: json['trainerMembershipId'] as String?,
        trainerName: json['trainerName'] as String?,
        status: json['status'] as String,
        startDate: _parseDate(json['startDate'] as String?),
        endDate: _parseDate(json['endDate'] as String?),
        trainers: ((json['trainers'] as List?) ?? const [])
            .map((t) => BatchTrainer.fromJson(t as Map<String, dynamic>))
            .toList(),
        studentCount: json['studentCount'] as int? ?? 0,
        startTime: json['startTime'] as String?,
        endTime: json['endTime'] as String?,
        days: ((json['days'] as List?) ?? const []).map((d) => Weekday.fromWire(d as String)).toList(),
        meetingLink: json['meetingLink'] as String?,
        courses: ((json['courses'] as List?) ?? const [])
            .map((c) => BatchCourse.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  static DateTime? _parseDate(String? iso) =>
      (iso == null || iso.isEmpty) ? null : DateTime.tryParse(iso);
}
