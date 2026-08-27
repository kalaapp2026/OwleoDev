import 'package:nest_fe/features/fees/data/fee_roster.dart';

/// Amount with Indian digit grouping - last three, then twos: 1,23,456.
///
/// Every amount in this app is read that way, and a plain thousands separator looks wrong to the
/// people reading it. Shared rather than per-screen so a rupee figure never renders two ways.
String money(num value) {
  final whole = value.round().abs().toString();
  final String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${value < 0 ? '-' : ''}₹$grouped';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// "4 Aug 2026" - day first, which is how dates are written and spoken here.
String formatFeeDate(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';

/// "Today" / "Yesterday" / "4 August 2026", for grouping a ledger into date sections.
///
/// Relative labels only for the two most recent days: past that they stop helping and start
/// making the reader do arithmetic.
String formatDateSectionLabel(DateTime? date) {
  if (date == null) return 'No payment yet';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  const full = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return '${date.day} ${full[date.month - 1]} ${date.year}';
}

/// The badge wording from the prototype. "Cash/UPI" rather than "Paid" because the distinction an
/// admin cares about is where the money physically is, not merely that it arrived.
String statusLabel(PaymentStatus status) => switch (status) {
      PaymentStatus.notPaid => 'Not Paid',
      PaymentStatus.due => 'Due',
      PaymentStatus.partial => 'Partial',
      PaymentStatus.paidManual => 'Cash/UPI',
      PaymentStatus.paidGateway => 'Gateway',
      PaymentStatus.closed => 'Closed',
    };

/// The API's period key: "2026-08".
String periodOf(DateTime month) =>
    '${month.year}-${month.month.toString().padLeft(2, '0')}';
