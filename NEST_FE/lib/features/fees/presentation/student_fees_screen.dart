import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_date_picker.dart';
import 'package:nest_fe/core/design/category_meta.dart';
import 'package:nest_fe/core/design/charts.dart';
import 'package:nest_fe/core/design/course_icons.dart';
import 'package:nest_fe/core/design/gold_tabs.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/export/report_export.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/curriculum/data/course.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/student_other_fees.dart';
import 'package:nest_fe/features/fees/data/student_statement.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;
import 'package:nest_fe/features/fees/presentation/student_pay_sheet.dart';

final _myRegularProvider = FutureProvider.autoDispose<StudentStatement>((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(feesApiProvider).myStatement();
});

final _myOtherProvider = FutureProvider.autoDispose<StudentOtherFees>((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(feesApiProvider).myOtherFees();
});

final _myCoursesProvider = FutureProvider.autoDispose<Map<String, Course>>((ref) async {
  final mid = ref.watch(activeMembershipIdProvider);
  if (mid == null) return {};
  final courses = await ref.watch(curriculumApiProvider).listCoursesForMembership(mid);
  return {for (final c in courses) c.id: c};
});

final _payEnabledProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(feesApiProvider).paymentsEnabled();
  } catch (_) {
    return false;
  }
});

enum _Tab { regular, other, statement }

/// One payment in the history: what it was for, how it was paid, when, how much.
typedef _Payment = ({String label, num amount, DateTime date, String mode, bool gateway});

/// "2026-08" -> "Aug 2026"; anything else (an Other fee's name) is left as written.
String _periodLabel(String raw) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw);
  if (m == null) return raw;
  final month = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return raw;
  return '${monthsShort[month - 1]} ${m.group(1)}';
}

/// The student's own Fees tab: Regular / Other / Statement. Reads `/me/fees/*`, which can only ever
/// return the caller's own rows. "Pay now" is on every unpaid fee; whether the payment can actually go
/// through depends on the academy having online payments switched on, which the pay sheet says plainly.
class StudentFeesScreen extends ConsumerStatefulWidget {
  const StudentFeesScreen({super.key});

  @override
  ConsumerState<StudentFeesScreen> createState() => _State();
}

class _State extends ConsumerState<StudentFeesScreen> {
  _Tab _tab = _Tab.regular;
  late DateTime _to = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  late DateTime _from = DateTime(_to.year, _to.month - 6, _to.day);

  void _refresh() {
    ref.invalidate(_myRegularProvider);
    ref.invalidate(_myOtherProvider);
  }

  /// Whether the academy has online payments switched on. The Pay button is always there so the
  /// student can see what paying looks like; this decides whether tapping it can go through.
  bool get _payAvailable => ref.read(_payEnabledProvider).valueOrNull ?? false;

  Future<void> _payRegular(StatementRow r) async {
    final paid = await showPaySheet(
      context: context,
      title: r.context,
      subtitle: _periodLabel(r.label),
      amount: r.balance,
      available: _payAvailable,
      onPay: (m) => ref.read(feesApiProvider).payMyFee(
          category: FeeCategory.regular, courseId: r.courseId, period: r.label, method: m),
    );
    if (paid) _refresh();
  }

  Future<void> _payOther(OtherFeeRow f) async {
    final paid = await showPaySheet(
      context: context,
      title: f.name,
      subtitle: f.custom ? 'One-time' : 'Academy fee',
      amount: f.outstanding,
      available: _payAvailable,
      onPay: (m) => ref.read(feesApiProvider).payMyFee(
          category: FeeCategory.other, feeTypeId: f.feeTypeId, studentFeeId: f.studentFeeId, method: m),
    );
    if (paid) _refresh();
  }

  bool _isGateway(String? mode) => (mode ?? '').toUpperCase() == 'GATEWAY';

  /// "Paid" / "Paid online" / "Partially paid" / "Due" - the student's vocabulary for the status.
  ({String label, Color color, Color soft}) _badge(PaymentStatus status, String? mode) {
    final p = context.palette;
    if (status.isSettled) {
      final online = status == PaymentStatus.paidGateway || _isGateway(mode);
      return (
        label: online ? 'Paid online' : 'Paid',
        color: online ? p.gateway : p.paidManual,
        soft: online ? p.gatewaySoft : p.paidManualSoft,
      );
    }
    if (status == PaymentStatus.partial) return (label: 'Partially paid', color: p.partial, soft: p.partialSoft);
    return (label: 'Due', color: p.notPaid, soft: p.notPaidSoft);
  }

  DateTime? _regularDue(StatementRow r, Map<String, Course> courses) {
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(r.label);
    final day = courses[r.courseId]?.dueDayOfMonth;
    if (m == null || day == null) return null;
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > last ? last : day);
  }

  void _showReceipt(String title, String subtitle, num amount, DateTime? date, String? mode) {
    showFeeReceipt(
      context: context,
      title: title,
      subtitle: subtitle,
      amount: amount,
      paidOn: date,
      via: _isGateway(mode) ? 'Online payment' : 'Academy (offline)',
    );
  }

  List<_Payment> _payments(StudentStatement s, StudentOtherFees? other) {
    return <_Payment>[
      for (final r in s.rows)
        if (r.paid > 0 && r.paidOn != null)
          (
            label: '${r.context} · ${_periodLabel(r.label)}',
            amount: r.paid,
            date: r.paidOn!,
            mode: _isGateway(r.mode) ? 'Gateway' : (r.mode == null ? 'Cash' : _titleCase(r.mode!)),
            gateway: _isGateway(r.mode),
          ),
      for (final f in other?.fees ?? const <OtherFeeRow>[])
        if (f.paid > 0 && f.lastPaidOn != null)
          (
            label: f.name,
            amount: f.paid,
            date: f.lastPaidOn!,
            mode: _isGateway(f.lastPaymentMode) ? 'Gateway' : (f.lastPaymentMode == null ? 'Cash' : _titleCase(f.lastPaymentMode!)),
            gateway: _isGateway(f.lastPaymentMode),
          ),
    ]..sort((a, b) => b.date.compareTo(a.date));
  }

  static String _titleCase(String v) => v.isEmpty ? v : v[0].toUpperCase() + v.substring(1).toLowerCase();

  @override
  Widget build(BuildContext context) {
    final regular = ref.watch(_myRegularProvider);
    final other = ref.watch(_myOtherProvider);
    final courses = ref.watch(_myCoursesProvider).valueOrNull ?? const <String, Course>{};

    int dueCount(Iterable<PaymentStatus> s) => s.where((x) => !x.isSettled).length;
    final regularDue = regular.maybeWhen(
        data: (s) => dueCount(s.rows.where((r) => r.category == FeeCategory.regular).map((r) => r.status)), orElse: () => 0);
    final otherDue = other.maybeWhen(data: (s) => dueCount(s.fees.map((f) => f.status)), orElse: () => 0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: AcademyPill(name: ref.watch(sessionControllerProvider).user?.activeMembership?.academyName ?? ''),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                GoldTabs<_Tab>(
                  options: _Tab.values,
                  alertBadges: true,
                  badgeOf: (t) => switch (t) {
                    _Tab.regular => regularDue,
                    _Tab.other => otherDue,
                    _Tab.statement => 0,
                  },
                  labelOf: (t) => switch (t) {
                    _Tab.regular => 'Regular',
                    _Tab.other => 'Other',
                    _Tab.statement => 'Statement',
                  },
                  selected: _tab,
                  onTap: (t) => setState(() => _tab = t),
                ),
                const SizedBox(height: 16),
                switch (_tab) {
                  _Tab.regular => AsyncValueView<StudentStatement>(
                      value: regular,
                      onRetry: () => ref.invalidate(_myRegularProvider),
                      data: (context, s) {
                        final rows = s.rows.where((r) => r.category == FeeCategory.regular).toList();
                        return _list(
                          billed: rows.fold<num>(0, (a, r) => a + r.fee),
                          paid: rows.fold<num>(0, (a, r) => a + r.paid),
                          pending: rows.where((r) => !r.status.isSettled).length,
                          title: 'Course fees',
                          cards: [
                            for (final r in rows)
                              _FeeCard(
                                course: courses[r.courseId],
                                title: r.context,
                                subtitle: _periodLabel(r.label),
                                amount: r.fee,
                                paid: r.paid,
                                badge: _badge(r.status, r.mode),
                                settled: r.status.isSettled,
                                partial: r.status == PaymentStatus.partial,
                                dueDate: _regularDue(r, courses),
                                paidOn: r.paidOn,
                                onPay: !r.status.isSettled && r.courseId != null ? () => _payRegular(r) : null,
                                onReceipt: r.status.isSettled
                                    ? () => _showReceipt(r.context, _periodLabel(r.label), r.paid, r.paidOn, r.mode)
                                    : null,
                              ),
                          ],
                          history: _payments(s, other.valueOrNull),
                        );
                      },
                    ),
                  _Tab.other => AsyncValueView<StudentOtherFees>(
                      value: other,
                      onRetry: () => ref.invalidate(_myOtherProvider),
                      data: (context, s) => _list(
                        billed: s.totalAmount,
                        paid: s.totalPaid,
                        pending: s.fees.where((f) => !f.status.isSettled).length,
                        title: 'Other fees',
                        cards: [
                          for (final f in s.fees)
                            _FeeCard(
                              title: f.name,
                              subtitle: f.custom ? 'One-time' : 'Academy fee',
                              amount: f.amount,
                              paid: f.paid,
                              badge: _badge(f.status, f.lastPaymentMode),
                              settled: f.status.isSettled,
                              partial: f.status == PaymentStatus.partial,
                              dueDate: f.dueDate,
                              paidOn: f.lastPaidOn,
                              onPay: !f.status.isSettled ? () => _payOther(f) : null,
                              onReceipt: f.status.isSettled
                                  ? () => _showReceipt(f.name, f.custom ? 'One-time' : 'Academy fee', f.paid, f.lastPaidOn, f.lastPaymentMode)
                                  : null,
                            ),
                        ],
                        history: _payments(regular.valueOrNull ?? StudentStatement.empty, s),
                      ),
                    ),
                  _Tab.statement => AsyncValueView<StudentStatement>(
                      value: regular,
                      onRetry: () => ref.invalidate(_myRegularProvider),
                      data: (context, s) => _statement(_payments(s, other.valueOrNull)),
                    ),
                },
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _list({
    required num billed,
    required num paid,
    required int pending,
    required String title,
    required List<Widget> cards,
    required List<_Payment> history,
  }) {
    final palette = context.palette;
    final due = (billed - paid).clamp(0, double.infinity);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.x3l),
          border: Border.all(color: palette.border),
        ),
        child: Row(children: [
          DonutChart(
              percent: billed > 0 ? paid / billed * 100 : 100,
              size: 64,
              strokeWidth: 7,
              color: due > 0 ? palette.primary : palette.paidManual),
          const SizedBox(width: 14),
          Expanded(
            child: Column(children: [
              _kv('Total due', money(due), due > 0 ? palette.notPaid : palette.paidManual, big: true),
              const SizedBox(height: 6),
              _kv('Paid so far', money(paid), palette.text),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    pending == 0
                        ? 'All caught up — no pending fees'
                        : '$pending item${pending > 1 ? 's' : ''} awaiting payment',
                    style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      Text(title, style: TextStyle(fontWeight: AppType.heavy, fontSize: 13.5, color: palette.text)),
      const SizedBox(height: 10),
      if (cards.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Text('Nothing here yet', style: TextStyle(fontSize: 12, color: palette.textFaint)),
        )
      else
        for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
      if (history.isNotEmpty) ...[
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Payment history', style: TextStyle(fontSize: 13.5, fontWeight: AppType.heavy, color: palette.text)),
            Pressable(
              onTap: () => setState(() => _tab = _Tab.statement),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Statement', style: TextStyle(fontSize: 11, fontWeight: AppType.bold, color: palette.primary)),
                Icon(Icons.chevron_right, size: 13, color: palette.primary),
              ]),
            ),
          ]),
        ),
        for (final p in history.take(2)) Padding(padding: const EdgeInsets.only(bottom: 8), child: _paymentRow(p)),
      ],
    ]);
  }

  Widget _paymentRow(_Payment p) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.border),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: p.gateway ? palette.gatewaySoft : palette.paidManualSoft, borderRadius: AppRadii.all(AppRadii.md)),
          child: Icon(Icons.check_circle_outline, size: 15, color: p.gateway ? palette.gateway : palette.paidManual),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: AppType.bold, fontSize: 12, color: palette.text)),
            const SizedBox(height: 2),
            Text('${p.mode} · ${formatFeeDate(p.date)}', style: TextStyle(fontSize: 10, color: palette.textFaint)),
          ]),
        ),
        Text(money(p.amount), style: TextStyle(fontWeight: AppType.heavy, fontSize: 12.5, color: palette.text)),
      ]),
    );
  }

  Widget _kv(String k, String v, Color color, {bool big = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(k, style: TextStyle(fontSize: 10.5, fontWeight: AppType.semi, color: context.palette.textMuted)),
          Text(v, style: TextStyle(fontSize: big ? 15 : 12.5, fontWeight: big ? AppType.heavy : AppType.bold, color: color)),
        ],
      );

  // ---- Statement tab -------------------------------------------------------------------------

  Widget _statement(List<_Payment> all) {
    final palette = context.palette;
    final inRange = all.where((p) => !p.date.isBefore(_from) && !p.date.isAfter(_to)).toList();
    final total = inRange.fold<num>(0, (a, p) => a + p.amount);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Payment statement', style: TextStyle(fontSize: 13.5, fontWeight: AppType.heavy, color: palette.text)),
      const SizedBox(height: 10),
      Row(children: [
        _rangeButton('From', _from, _setFrom, max: _to),
        const SizedBox(width: 8),
        _rangeButton('To', _to, _setTo, min: _from, max: DateTime.now()),
      ]),
      const SizedBox(height: 8),
      Text('Statements can cover up to a 6-month range', style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${inRange.length} transaction${inRange.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 10.5, fontWeight: AppType.semi, color: palette.textMuted)),
              const SizedBox(height: 2),
              Text(money(total), style: TextStyle(fontSize: 16, fontWeight: AppType.heavy, color: palette.text)),
            ]),
          ),
          Pressable(
            onTap: inRange.isEmpty ? null : () => _download(inRange, total),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: inRange.isEmpty ? palette.surfaceHigh : palette.primary,
                borderRadius: AppRadii.all(11),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.download_outlined, size: 14, color: inRange.isEmpty ? palette.textFaint : palette.onPrimary),
                const SizedBox(width: 6),
                Text('Download',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: AppType.bold,
                        color: inRange.isEmpty ? palette.textFaint : palette.onPrimary)),
              ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      if (inRange.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Text('No transactions in this range',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: palette.textFaint)),
        ),
      for (final p in inRange) Padding(padding: const EdgeInsets.only(bottom: 8), child: _paymentRow(p)),
    ]);
  }

  void _setFrom(DateTime d) {
    setState(() {
      _from = d.isAfter(_to) ? _to : d;
      final limit = DateTime(_to.year, _to.month - 6, _to.day);
      if (_from.isBefore(limit)) {
        _to = DateTime(_from.year, _from.month + 6, _from.day);
        if (_to.isAfter(DateTime.now())) _to = DateTime.now();
        showAppToast(context, 'Statements are limited to a 6-month range');
      }
    });
  }

  void _setTo(DateTime d) {
    setState(() {
      _to = d.isBefore(_from) ? _from : d;
      final limit = DateTime(_to.year, _to.month - 6, _to.day);
      if (_from.isBefore(limit)) {
        _from = limit;
        showAppToast(context, 'Statements are limited to a 6-month range');
      }
    });
  }

  Widget _rangeButton(String label, DateTime v, ValueChanged<DateTime> onPick, {DateTime? min, DateTime? max}) {
    final palette = context.palette;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: AppType.semi, color: palette.textMuted)),
        const SizedBox(height: 4),
        Pressable(
          onTap: () async {
            final picked = await showAppDatePicker(
                context: context, title: 'Statement $label'.toLowerCase(), value: v, minDate: min, maxDate: max);
            if (picked != null) onPick(DateTime(picked.year, picked.month, picked.day));
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.md),
              border: Border.all(color: palette.border),
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_outlined, size: 13, color: palette.textFaint),
              const SizedBox(width: 6),
              Text(formatFeeDate(v), style: TextStyle(fontSize: 12, fontWeight: AppType.semi, color: palette.text)),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _download(List<_Payment> rows, num total) async {
    final format = await showDownloadFormatSheet(context, title: 'Download statement as');
    if (format == null || !mounted) return;
    final user = ref.read(sessionControllerProvider).user;
    final table = ReportTable(
      title: 'Payment Statement — ${user?.fullName ?? ''}',
      subtitle: '${user?.activeMembership?.academyName ?? ''} · ${formatFeeDate(_from)} – ${formatFeeDate(_to)}',
      headers: const ['Date', 'Fee', 'Mode', 'Amount'],
      rows: [for (final p in rows) [formatFeeDate(p.date), p.label, p.mode, money(p.amount)]],
      totalLabel: 'Total paid',
      totalValue: money(total),
      fileStem: '${user?.fullName ?? 'student'}_statement_${_from.toIso8601String().substring(0, 10)}_to_${_to.toIso8601String().substring(0, 10)}',
      sheetName: 'Statement',
    );
    try {
      await shareReport(table, format);
      if (mounted) {
        showAppToast(context, format == ReportFormat.pdf ? 'Statement PDF ready to save' : 'Excel statement downloaded');
      }
    } catch (_) {
      if (mounted) {
        showAppToast(context, format == ReportFormat.pdf ? "Couldn't create the PDF" : "Couldn't generate the Excel file",
            error: true);
      }
    }
  }
}

class _FeeCard extends StatelessWidget {
  const _FeeCard({
    this.course,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.paid,
    required this.badge,
    required this.settled,
    required this.partial,
    this.dueDate,
    this.paidOn,
    this.onPay,
    this.onReceipt,
  });

  final Course? course;
  final VoidCallback? onPay;
  final VoidCallback? onReceipt;
  final String title;
  final String subtitle;
  final num amount;
  final num paid;
  final ({String label, Color color, Color soft}) badge;
  final bool settled;
  final bool partial;
  final DateTime? dueDate;
  final DateTime? paidOn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final balance = amount - paid;
    // A course fee takes its course's icon and colour; an Other fee is a gold package.
    final meta = course?.category.meta(palette);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.border),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: meta?.soft ?? palette.goldSoft, borderRadius: AppRadii.all(11)),
            child: Center(
              child: course == null
                  ? Icon(Icons.inventory_2_outlined, size: 17, color: palette.gold)
                  : CourseIcon.forCourse(iconKey: course!.iconKey, category: course!.category, color: meta!.color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: AppType.bold, fontSize: 13, color: palette.text)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: badge.soft, borderRadius: AppRadii.all(AppRadii.sm)),
            child: Text(badge.label, style: TextStyle(fontSize: 9.5, fontWeight: AppType.bold, color: badge.color)),
          ),
        ]),
        const SizedBox(height: 10),
        _DashedDivider(color: palette.borderSoft),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(money(amount), style: TextStyle(fontSize: 16, fontWeight: AppType.heavy, color: palette.text)),
            if (partial)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text('${money(balance)} balance remaining',
                    style: TextStyle(fontSize: 9.5, fontWeight: AppType.semi, color: palette.partial)),
              ),
            if (!settled && dueDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.schedule, size: 10, color: palette.textFaint),
                  const SizedBox(width: 3),
                  Text('Due ${formatFeeDate(dueDate!)}', style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
                ]),
              ),
            if (settled && paidOn != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Paid on ${formatFeeDate(paidOn!)}', style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
              ),
          ]),
          if (onPay != null)
            Pressable(
              onTap: onPay,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: AppRadii.all(AppRadii.md),
                  boxShadow: [BoxShadow(color: palette.primary.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.credit_card, size: 13, color: palette.onPrimary),
                  const SizedBox(width: 5),
                  Text('Pay now', style: TextStyle(fontSize: 11.5, fontWeight: AppType.bold, color: palette.onPrimary)),
                ]),
              ),
            )
          else if (onReceipt != null)
            Pressable(
              onTap: onReceipt,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: AppRadii.all(AppRadii.md),
                  border: Border.all(color: palette.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.receipt_long_outlined, size: 12.5, color: palette.textMuted),
                  const SizedBox(width: 4),
                  Text('Receipt', style: TextStyle(fontSize: 11, fontWeight: AppType.bold, color: palette.textMuted)),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final count = (c.maxWidth / 6).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [for (var i = 0; i < count; i++) Container(width: 3, height: 1, color: color)],
      );
    });
  }
}
