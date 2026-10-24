import 'package:flutter/material.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/export/report_export.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart';
import 'package:nest_fe/features/fees/data/transaction_ledger.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';

/// The Fees module's downloadable reports - PDF or Excel, picked from the same sheet the rest of the
/// app uses. Each builds a [ReportTable] from what is ON SCREEN (the filtered list, the narrowed
/// ledger) rather than refetching: a report that quietly widens past the filter the admin set is
/// worse than none, because it gets sent to a parent.

String _mode(String? mode) => switch ((mode ?? '').toUpperCase()) {
      'CASH' => 'Cash',
      'UPI' => 'UPI',
      'GATEWAY' => 'Gateway',
      _ => '-',
    };

String _date(DateTime? d) => d == null ? '-' : formatFeeDate(d);

/// "2026-08" -> "August 2026"; anything else (an Other fee's name) as written.
String _periodName(String raw) {
  final parts = raw.split('-');
  if (parts.length != 2) return raw;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return raw;
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return '${names[month - 1]} $year';
}

Future<void> _share(BuildContext context, ReportTable table, ReportFormat format) async {
  try {
    await shareReport(table, format);
    if (context.mounted) {
      showAppToast(
          context, format == ReportFormat.pdf ? 'Report PDF ready to save' : 'Excel report downloaded');
    }
  } catch (_) {
    if (context.mounted) {
      showAppToast(
          context,
          format == ReportFormat.pdf ? "Couldn't create the PDF" : "Couldn't generate the Excel file",
          error: true);
    }
  }
}

/// A batch's students for one fee: billed, collected, outstanding, and each row.
Future<void> shareRosterReport(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<FeeRosterEntry> entries,
}) async {
  final format = await showDownloadFormatSheet(context, title: 'Download report as');
  if (format == null || !context.mounted) return;

  final billed = entries.fold<num>(0, (a, e) => a + e.agreedFee);
  final collected = entries.fold<num>(0, (a, e) => a + e.totalPaid);
  await _share(
    context,
    ReportTable(
      title: 'Fee Collection Report',
      subtitle: [title, subtitle].where((s) => s.isNotEmpty).join(' · '),
      meta: [
        ('Students', '${entries.length}'),
        ('Total billed', money(billed)),
        ('Total collected', money(collected)),
        ('Outstanding', money(billed - collected)),
      ],
      headers: const ['#', 'Student', 'Fee', 'Paid', 'Balance', 'Status', 'Mode', 'Payment date'],
      rows: [
        for (var i = 0; i < entries.length; i++)
          [
            '${i + 1}',
            entries[i].studentName,
            money(entries[i].agreedFee),
            money(entries[i].totalPaid),
            money(entries[i].agreedFee - entries[i].totalPaid),
            statusLabel(entries[i].status),
            _mode(entries[i].lastPaymentMode),
            _date(entries[i].lastPaidOn),
          ],
      ],
      fileStem: 'fee_report_$title',
      sheetName: 'Fee Report',
    ),
    format,
  );
}

/// The academy's ledger over whatever range and filter the screen is showing.
Future<void> shareLedgerReport(
  BuildContext context, {
  required String periodLabel,
  required TransactionLedger ledger,
}) async {
  final format = await showDownloadFormatSheet(context, title: 'Download report as');
  if (format == null || !context.mounted) return;

  await _share(
    context,
    ReportTable(
      title: 'All Transactions - Regular + Other Fees',
      subtitle: periodLabel,
      meta: [
        ('Regular Fees', money(ledger.regularTotal)),
        ('Other Fees', money(ledger.otherTotal)),
        ('Total', money(ledger.total)),
      ],
      headers: const ['#', 'Student', 'Category', 'For', 'Amount', 'Mode', 'Date'],
      rows: [
        for (var i = 0; i < ledger.entries.length; i++)
          [
            '${i + 1}',
            ledger.entries[i].studentName,
            ledger.entries[i].category.label,
            ledger.entries[i].context,
            money(ledger.entries[i].amount),
            _mode(ledger.entries[i].mode),
            _date(ledger.entries[i].occurredOn),
          ],
      ],
      fileStem: 'all_transactions_$periodLabel',
      sheetName: 'Transactions',
    ),
    format,
  );
}

/// One student's statement, as filtered on screen.
Future<void> shareStatementReport(
  BuildContext context, {
  required StudentStatement statement,
}) async {
  final format = await showDownloadFormatSheet(context, title: 'Download statement as');
  if (format == null || !context.mounted) return;

  await _share(
    context,
    ReportTable(
      title: 'Fee Statement - ${statement.studentName}',
      subtitle: 'Regular + Other fees combined',
      meta: [
        ('Total billed', money(statement.totalBilled)),
        ('Total paid', money(statement.totalPaid)),
        ('Outstanding balance', money(statement.outstanding)),
      ],
      headers: const ['Period', 'Category', 'For', 'Fee', 'Paid', 'Balance', 'Status', 'Payment date'],
      rows: [
        for (final r in statement.rows)
          [
            _periodName(r.label),
            r.category.label,
            r.context.isEmpty ? '-' : r.context,
            money(r.fee),
            money(r.paid),
            money(r.fee - r.paid),
            statusLabel(r.status),
            _date(r.paidOn),
          ],
      ],
      fileStem: '${statement.studentName}_fee_statement',
      sheetName: 'Fee Statement',
    ),
    format,
  );
}
