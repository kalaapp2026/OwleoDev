import 'package:intl/intl.dart';

/// Number and date formatting, ported from the prototype's `inr`, `short`, `num`, `pct` helpers.
/// Indian digit grouping (1,23,456) throughout, because that is how the owners read money.

final _indian = NumberFormat.decimalPattern('en_IN');

/// `₹1,23,456`. Negative amounts keep the sign in front of the symbol, like the prototype.
String inr(num n) => '${n < 0 ? '-' : ''}₹${_indian.format(n.abs().round())}';

String _trim(String s) => s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;

/// `₹1.2L`, `₹3.4Cr`, `₹8.5k`. For chart axes and tight tiles.
String short(num n) {
  final a = n.abs();
  final s = n < 0 ? '-' : '';
  if (a >= 1e7) return '$s₹${_trim((a / 1e7).toStringAsFixed(2))}Cr';
  if (a >= 1e5) return '$s₹${_trim((a / 1e5).toStringAsFixed(2))}L';
  if (a >= 1e3) return '$s₹${_trim((a / 1e3).toStringAsFixed(a >= 1e4 ? 0 : 1))}k';
  return '$s₹${a.round()}';
}

String num0(num n) => _indian.format(n.round());

String pct(num n) => '${n.round()}%';

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
  return parts.map((w) => w[0]).join().toUpperCase();
}

final _dMy = DateFormat('d MMM yyyy');
final _dM = DateFormat('d MMM');

/// `5 Oct 2026` from an ISO date or timestamp, or '' when absent.
String fd(Object? v) {
  final d = toDate(v);
  return d == null ? '' : _dMy.format(d);
}

/// `5 Oct` (no year).
String fdShort(Object? v) {
  final d = toDate(v);
  return d == null ? '' : _dM.format(d);
}

DateTime? toDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  return DateTime.tryParse(v.toString())?.toLocal();
}

/// "2 min ago", "3 hr ago", "Yesterday", "12 Sep" - for activity feeds.
String ago(Object? v) {
  final d = toDate(v);
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return _dM.format(d);
}

/// Reads a JSON number that the server may have sent as int, double or string.
double dbl(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

int int0(Object? v) => v is num ? v.round() : int.tryParse('$v') ?? 0;

/// Month labels for the 12-month charts. The server sends 'YYYY-MM'.
const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String monthShort(String ym) => _mon[int.parse(ym.substring(5, 7)) - 1];
String monthLong(String ym) => '${monthShort(ym)} ${ym.substring(0, 4)}';
