/// Amount and date formatting shared across modules.
///
/// Lived in the Fees feature until Course Creation needed the same rupee formatting. A second
/// copy would have drifted, so it moved here rather than being duplicated - `fee_format.dart`
/// re-exports it, which is why no Fees call site changed.
library;

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

const monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

const monthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

/// "4 Aug 2026" - day first, which is how dates are written and spoken here.
String formatFeeDate(DateTime date) => '${date.day} ${monthsShort[date.month - 1]} ${date.year}';

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
  return '${date.day} ${monthsFull[date.month - 1]} ${date.year}';
}

/// The API's period key: "2026-08".
String periodOf(DateTime month) =>
    '${month.year}-${month.month.toString().padLeft(2, '0')}';

/// "2" -> "2nd", "23" -> "23rd". Used wherever a day-of-month is shown as prose - the billing
/// and payment-due day pickers, and the course list's billing summary.
String ordinalDay(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}
