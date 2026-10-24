import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart' show FeeCategory;
import 'package:nest_fe/features/fees/data/fees_api.dart' show feesApiProvider;

/// What the student still owes, with the most pressing item to name on the dashboard's Due card.
typedef FeeDue = ({num amount, String? line, DateTime? due});

final myFeeDueProvider = FutureProvider.autoDispose<FeeDue>((ref) async {
  final statement = await ref.watch(feesApiProvider).myStatement();
  final other = await ref.watch(feesApiProvider).myOtherFees();
  final unpaidOther = other.fees.where((f) => !f.status.isSettled).toList()
    ..sort((a, b) => (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999)));
  final unpaidRegular =
      statement.rows.where((r) => r.category == FeeCategory.regular && !r.status.isSettled).toList();
  // A fee with a due date outranks one without; otherwise the course fee is the headline.
  final datedOther = unpaidOther.where((f) => f.dueDate != null).toList();
  String? line;
  DateTime? due;
  if (datedOther.isNotEmpty) {
    line = datedOther.first.name;
    due = datedOther.first.dueDate;
  } else if (unpaidRegular.isNotEmpty) {
    line = '${unpaidRegular.first.context} · ${unpaidRegular.first.label}';
  } else if (unpaidOther.isNotEmpty) {
    line = unpaidOther.first.name;
  }
  return (amount: statement.outstanding + other.outstanding, line: line, due: due);
});
