import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/enrolment/presentation/student_roster_picker.dart';
import 'package:nest_fe/features/fees/data/fee_transaction.dart';
import 'package:nest_fe/features/fees/data/fees_api.dart';
import 'package:share_plus/share_plus.dart';

final feesApiProvider = Provider((ref) => FeesApi(ref.watch(dioClientProvider)));

class FeesScreen extends ConsumerStatefulWidget {
  const FeesScreen({super.key});

  @override
  ConsumerState<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends ConsumerState<FeesScreen> {
  final _periodController = TextEditingController(text: _currentPeriod());
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _gatewayRefController = TextEditingController();
  String? _selectedCourseId;
  String? _selectedMembershipId;
  String _mode = 'CASH';
  bool _closeOnCustomAmount = false;

  List<FeeTransaction>? _history;
  List<FeeSlip>? _feeSlips;
  FeeBalance? _balance;
  bool _isLoading = false;
  bool _isRecording = false;
  bool _isDownloading = false;

  static String _currentPeriod() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _lookup() async {
    final membershipId = _selectedMembershipId;
    final courseId = _selectedCourseId;
    if (membershipId == null || courseId == null) return;

    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ref.read(feesApiProvider).historyForStudent(membershipId),
        ref.read(feesApiProvider).balance(membershipId: membershipId, courseId: courseId, period: _periodController.text.trim()),
        ref.read(feesApiProvider).feeSlipHistory(membershipId),
      ]);
      setState(() {
        _history = results[0] as List<FeeTransaction>;
        _balance = results[1] as FeeBalance;
        _feeSlips = results[2] as List<FeeSlip>;
      });
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _recordEntry(num amount, {required bool closePeriod}) async {
    if (_selectedCourseId == null || _selectedMembershipId == null) return;
    setState(() => _isRecording = true);
    try {
      await ref.read(feesApiProvider).recordEntry(
            membershipId: _selectedMembershipId!,
            courseId: _selectedCourseId!,
            period: _periodController.text.trim(),
            amountPaid: amount,
            mode: _mode,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
            gatewayRef: _mode == 'GATEWAY' && _gatewayRefController.text.trim().isNotEmpty ? _gatewayRefController.text.trim() : null,
            closePeriod: closePeriod,
          );
      _amountController.clear();
      _noteController.clear();
      if (mounted) AppNotice.success(context, 'Payment recorded.');
      await _lookup();
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _payInFull() async {
    final balance = _balance;
    if (balance == null || balance.balance <= 0) return;
    await _recordEntry(balance.balance, closePeriod: true);
  }

  Future<void> _payCustomAmount() async {
    final amount = num.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      AppNotice.error(context, 'Enter a valid amount.');
      return;
    }
    await _recordEntry(amount, closePeriod: _closeOnCustomAmount);
  }

  Future<void> _downloadReport() async {
    if (_selectedCourseId == null) return;
    setState(() => _isDownloading = true);
    try {
      final bytes = await ref.read(feesApiProvider).downloadReport(courseId: _selectedCourseId!, period: _periodController.text.trim());
      final filename = 'fees-report-${_periodController.text.trim()}.csv';
      await Share.shareXFiles(
        [XFile.fromData(Uint8List.fromList(bytes), name: filename, mimeType: 'text/csv')],
        text: 'Fees report for ${_periodController.text.trim()}',
      );
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).user;
    final isAdmin = user != null && (user.isSuperAdmin || user.isActiveAcademyAdmin);
    // An Admin picks from every course in the academy; a Trainer only from courses they're
    // actually mapped to - same scoping already applied to Course Materials.
    final coursesAsync = isAdmin || user?.activeMembershipId == null
        ? ref.watch(activeCoursesProvider)
        : ref.watch(coursesForMembershipProvider(user!.activeMembershipId!));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Look up a student', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                coursesAsync.when(
                  data: (courses) {
                    if (courses.isEmpty) {
                      return const Text('No courses available to you yet.', style: TextStyle(fontSize: 12.5));
                    }
                    final validValue = courses.any((c) => c.id == _selectedCourseId) ? _selectedCourseId : null;
                    return DropdownButtonFormField<String>(
                      initialValue: validValue,
                      decoration: const InputDecoration(labelText: 'Course'),
                      items: courses.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                      onChanged: (id) => setState(() {
                        _selectedCourseId = id;
                        _selectedMembershipId = null;
                        _balance = null;
                      }),
                    );
                  },
                  loading: () => const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  error: (err, stack) => Text(
                    err is ApiException ? err.message : 'Could not load courses',
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                  ),
                ),
                if (_selectedCourseId != null) ...[
                  const SizedBox(height: 10),
                  Consumer(
                    builder: (context, ref, _) {
                      final studentsAsync = ref.watch(studentsForCourseProvider(_selectedCourseId!));
                      return studentsAsync.when(
                        data: (students) {
                          if (students.isEmpty) {
                            return const Text('No students enrolled in this course yet.', style: TextStyle(fontSize: 12.5));
                          }
                          final validValue = students.any((s) => s.membershipId == _selectedMembershipId) ? _selectedMembershipId : null;
                          return DropdownButtonFormField<String>(
                            initialValue: validValue,
                            decoration: const InputDecoration(labelText: 'Student'),
                            items: students.map((s) => DropdownMenuItem(value: s.membershipId, child: Text(s.fullName))).toList(),
                            onChanged: (id) => setState(() => _selectedMembershipId = id),
                          );
                        },
                        loading: () => const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                        error: (err, stack) => Text(
                          err is ApiException ? err.message : 'Could not load students for this course',
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 10),
                TextField(controller: _periodController, decoration: const InputDecoration(labelText: 'Period (YYYY-MM)')),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading || _selectedMembershipId == null ? null : _lookup,
                        child: _isLoading
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Look up'),
                      ),
                    ),
                    if (_selectedCourseId != null) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _isDownloading ? null : _downloadReport,
                        icon: _isDownloading
                            ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Report'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_balance != null) ...[
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _BalanceStat(label: 'Agreed fee', value: _balance!.agreedFee),
                      _BalanceStat(label: 'Paid', value: _balance!.totalPaid),
                      _BalanceStat(label: 'Balance', value: _balance!.balance, highlight: true),
                    ],
                  ),
                  if (_balance!.closed) ...[
                    const SizedBox(height: 10),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('Closed - remainder written off'),
                      avatar: const Icon(Icons.lock_outline, size: 16),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Record a payment', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _mode,
                    decoration: const InputDecoration(labelText: 'Mode'),
                    items: const [
                      DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                      DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                      DropdownMenuItem(value: 'GATEWAY', child: Text('Payment gateway')),
                    ],
                    onChanged: (v) => setState(() => _mode = v!),
                  ),
                  if (_mode == 'GATEWAY') ...[
                    const SizedBox(height: 10),
                    TextField(controller: _gatewayRefController, decoration: const InputDecoration(labelText: 'Gateway reference')),
                  ],
                  const SizedBox(height: 10),
                  TextField(controller: _noteController, decoration: const InputDecoration(labelText: 'Note (optional)')),
                  const SizedBox(height: 14),
                  if (_balance!.balance > 0)
                    ElevatedButton.icon(
                      onPressed: _isRecording ? null : _payInFull,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text('Mark as paid (₹${_balance!.balance})'),
                    ),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 10),
                  Text('Or enter an amount', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (₹)'),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Partial pay'), icon: Icon(Icons.arrow_forward, size: 16)),
                      ButtonSegment(value: true, label: Text('Close'), icon: Icon(Icons.lock_outline, size: 16)),
                    ],
                    selected: {_closeOnCustomAmount},
                    onSelectionChanged: (s) => setState(() => _closeOnCustomAmount = s.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _closeOnCustomAmount
                          ? 'The remaining balance will NOT carry forward to next period.'
                          : 'Any remaining balance will carry forward to next period.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _isRecording ? null : _payCustomAmount,
                    child: _isRecording
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Record payment'),
                  ),
                ],
              ),
            ),
          ),
          if ((_feeSlips ?? const []).where((s) => s.courseId == _selectedCourseId).isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Fee slips', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...(_feeSlips ?? const [])
                .where((s) => s.courseId == _selectedCourseId)
                .map((slip) => Card(
                      child: ListTile(
                        leading: Icon(slip.isClosed ? Icons.lock_outline : Icons.receipt_long_outlined),
                        title: Text('₹${slip.amountDue} · ${slip.period}'),
                        subtitle: Text([
                          '${slip.billingPeriodStart} to ${slip.billingPeriodEnd}',
                          if (slip.classesHeld != null) '${slip.classesAttended ?? 0} of ${slip.classesHeld} classes attended',
                          if (slip.carriedForwardAmount > 0) '₹${slip.carriedForwardAmount} carried from last period',
                          if (slip.isClosed) 'Closed',
                        ].join(' · ')),
                      ),
                    )),
          ],
          const SizedBox(height: 16),
          Text('History', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...(_history ?? []).map((tx) => Card(
                child: ListTile(
                  leading: Icon(switch (tx.mode) {
                    'CASH' => Icons.payments_outlined,
                    'UPI' => Icons.qr_code_2_outlined,
                    _ => Icons.credit_card_outlined,
                  }),
                  title: Text('₹${tx.amountPaid} · ${tx.period}'),
                  subtitle: Text(tx.note ?? tx.mode),
                ),
              )),
        ],
      ],
    );
  }
}

class _BalanceStat extends StatelessWidget {
  const _BalanceStat({required this.label, required this.value, this.highlight = false});
  final String label;
  final num value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          '₹$value',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: highlight ? colorScheme.primary : null,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
