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
  });

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
      );

  static DateTime? _parseDate(String? iso) =>
      (iso == null || iso.isEmpty) ? null : DateTime.tryParse(iso);
}
