import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/features/fees/data/fee_roster.dart';
import 'package:nest_fe/features/fees/data/fee_type.dart';
import 'package:nest_fe/features/fees/presentation/add_fee_type_screen.dart';
import 'package:nest_fe/features/fees/presentation/fee_format.dart';
import 'package:nest_fe/features/fees/presentation/fees_screen.dart' show feesApiProvider;
import 'package:nest_fe/features/fees/presentation/widgets/student_list_body.dart';

final feeTypesProvider = FutureProvider.autoDispose<List<FeeType>>((ref) {
  return ref.watch(feesApiProvider).feeTypes();
});

typedef _OtherRosterKey = ({String feeTypeId, String batchId});

final _otherRosterProvider =
    FutureProvider.autoDispose.family<FeeRoster, _OtherRosterKey>((ref, key) {
  return ref.watch(feesApiProvider).otherRoster(
        feeTypeId: key.feeTypeId,
        batchId: key.batchId,
      );
});

enum _OpenPanel { none, feeType, batch }

/// Other Fees: fee type -> batch, then the batch's students.
///
/// Unlike a regular fee the amount is the same for everyone - a costume costs what it costs - so
/// there is no per-student agreed figure, only who has paid it.
class OtherFeesScreen extends ConsumerStatefulWidget {
  const OtherFeesScreen({super.key});

  @override
  ConsumerState<OtherFeesScreen> createState() => _OtherFeesScreenState();
}

class _OtherFeesScreenState extends ConsumerState<OtherFeesScreen> {
  FeeType? _feeType;
  FeeTypeBatchBinding? _batch;
  _OpenPanel _open = _OpenPanel.none;
  bool _selectorsVisible = true;
  bool _busy = false;

  _OtherRosterKey? get _rosterKey => (_feeType != null && _batch != null)
      ? (feeTypeId: _feeType!.id, batchId: _batch!.batchId)
      : null;

  void _selectFeeType(FeeType type) {
    setState(() {
      _feeType = type;
      // A fee bound to exactly one batch has nothing to choose, so it is picked for the admin.
      // Otherwise the old batch belonged to a different fee and cannot carry over.
      _batch = type.onlyBatch;
    });
  }

  void _refresh() {
    final key = _rosterKey;
    if (key != null) ref.invalidate(_otherRosterProvider(key));
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _markPaid(FeeRosterEntry entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(feesApiProvider).recordOtherPayment(
            membershipId: entry.membershipId,
            feeTypeId: _feeType!.id,
            amountPaid: entry.balance,
            mode: _feeType!.defaultMode ?? 'CASH',
          );
      _refresh();
      if (mounted) showAppToast(context, '${entry.studentName} marked as Paid');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(FeeRosterEntry entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(feesApiProvider).reverseEntry(transactionId: entry.lastPaymentId!);
      _refresh();
      if (mounted) showAppToast(context, '${entry.studentName} reverted to Not Paid');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createFeeType() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddFeeTypeScreen()),
    );
    if (created == true) {
      ref.invalidate(feeTypesProvider);
      if (mounted) showAppToast(context, 'Fee type created');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final typesAsync = ref.watch(feeTypesProvider);
    final key = _rosterKey;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        title: const Text('Other Fees'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xs, AppSpacing.xl, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _feeType != null && _batch != null
                    ? '${_feeType!.name} · ${_batch!.label}'
                    : 'Select fee type & batch',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.smd, color: palette.textMuted),
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.collapse,
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: _selectorsVisible
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xs),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: typesAsync.when(
                                loading: () => const _SelectorPlaceholder(),
                                error: (e, _) => _Inline(message: 'Fee types failed to load', error: e),
                                data: (types) => AttachedSelect<FeeType>(
                                  label: 'Fee type',
                                  placeholder: 'Select fee type',
                                  options: types,
                                  labelOf: (t) => t.name,
                                  value: _feeType == null
                                      ? null
                                      : types.where((t) => t.id == _feeType!.id).firstOrNull,
                                  searchable: types.length > 6,
                                  isOpen: _open == _OpenPanel.feeType,
                                  onOpenChanged: (o) => setState(
                                      () => _open = o ? _OpenPanel.feeType : _OpenPanel.none),
                                  emptyLabel: 'No fee types yet',
                                  // The amount belongs on the row: an admin picking "Costume Fee"
                                  // is choosing an amount as much as a name.
                                  optionBuilder: (context, type, selected) => Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          type.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: AppType.lg,
                                            fontWeight:
                                                selected ? AppType.bold : AppType.regular,
                                            color: selected ? palette.primary : palette.text,
                                          ),
                                        ),
                                      ),
                                      Text(money(type.amount),
                                          style: TextStyle(
                                              fontSize: AppType.md, color: palette.textMuted)),
                                    ],
                                  ),
                                  onSelected: _selectFeeType,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            _AddButton(onTap: _createFeeType),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AttachedSelect<FeeTypeBatchBinding>(
                          label: 'Batch',
                          placeholder: _feeType == null
                              ? 'Select a fee type first'
                              : 'Select batch',
                          options: _feeType?.batches ?? const [],
                          labelOf: (b) => b.label,
                          value: _batch,
                          enabled: _feeType != null,
                          // Locked both when there's no fee type yet and when the fee applies to
                          // exactly one batch - in both cases there is nothing to decide.
                          locked: _feeType == null || _feeType!.onlyBatch != null,
                          searchable: (_feeType?.batches.length ?? 0) > 6,
                          isOpen: _open == _OpenPanel.batch,
                          onOpenChanged: (o) =>
                              setState(() => _open = o ? _OpenPanel.batch : _OpenPanel.none),
                          onSelected: (b) => setState(() => _batch = b),
                        ),
                        if (_feeType != null && _feeType!.batches.length > 1) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'This fee applies to ${_feeType!.batches.length} batches - pick which one to view.',
                              style:
                                  TextStyle(fontSize: AppType.xs, color: palette.textFaint),
                            ),
                          ),
                        ],
                        if (_feeType?.dueDate != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _DueBanner(dueDate: _feeType!.dueDate!),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (key == null)
            Expanded(
              child: _Empty(
                message: _feeType == null
                    ? 'Select a fee type and batch above\nto see the student list'
                    : 'Select a batch above\nto see the student list',
              ),
            )
          else
            Expanded(
              child: ref.watch(_otherRosterProvider(key)).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _Inline(message: 'Could not load the list', error: e),
                    data: (roster) => StudentListBody(
                      roster: roster,
                      busy: _busy,
                      emptyText: 'No students in this batch yet.',
                      onMarkPaid: _markPaid,
                      onUndo: _undo,
                      onOpenProfile: (entry) => showAppToast(
                          context, "The Other side of a student's profile is still to come"),
                      onScrolled: (scrolled) =>
                          setState(() => _selectorsVisible = !scrolled),
                    ),
                  ),
            ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.primarySoft,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: palette.primaryDim),
        ),
        child: Icon(Icons.add_rounded, size: 20, color: palette.primary),
      ),
    );
  }
}

class _DueBanner extends StatelessWidget {
  const _DueBanner({required this.dueDate});

  final DateTime dueDate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.partialSoft,
        borderRadius: AppRadii.all(AppRadii.lg),
        border: Border.all(color: palette.partial),
      ),
      child: Row(
        children: [
          Icon(Icons.event_outlined, size: 15, color: palette.partial),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Last date to pay: ${formatFeeDate(dueDate)}',
              style: TextStyle(
                fontSize: AppType.smd,
                fontWeight: AppType.semi,
                color: palette.partial,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectorPlaceholder extends StatelessWidget {
  const _SelectorPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: AppRadii.all(AppRadii.lg),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 26, color: palette.textFaint),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.lg, color: palette.textFaint, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Inline extends StatelessWidget {
  const _Inline({required this.message, required this.error});

  final String message;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 28, color: palette.notPaid),
            const SizedBox(height: AppSpacing.sm),
            Text(message,
                style: TextStyle(
                    fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              error.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.xs, color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
