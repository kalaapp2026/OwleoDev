import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/export/report_export.dart';
import 'package:nest_fe/core/format/money.dart';

const _methods = [
  (key: 'UPI', label: 'UPI', sub: 'Google Pay, PhonePe, Paytm', icon: Icons.smartphone_outlined),
  (key: 'CARD', label: 'Credit / Debit Card', sub: 'Visa, Mastercard, RuPay', icon: Icons.credit_card_outlined),
  (key: 'NETBANKING', label: 'Netbanking', sub: 'All major banks', icon: Icons.account_balance_outlined),
];

/// The student's pay flow: confirm the amount, pick a method, pay, then a success screen with a
/// reference and a receipt to download. [onPay] performs the payment and returns its reference; the
/// amount shown is only for display - the server decides what is actually owed.
Future<bool> showPaySheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required num amount,
  required Future<String> Function(String method) onPay,
}) async {
  final paid = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _PaySheet(title: title, subtitle: subtitle, amount: amount, onPay: onPay),
  );
  return paid ?? false;
}

/// A receipt as a PDF, shared through the platform sheet (a download on web).
Future<void> downloadReceiptPdf({
  required String title,
  required String subtitle,
  required num amount,
  required String via,
  required DateTime date,
  String reference = '',
}) {
  return shareReport(
    ReportTable(
      title: 'Payment receipt',
      subtitle: [title, if (subtitle.isNotEmpty) subtitle].join(' · '),
      meta: [
        ('Amount paid', money(amount)),
        ('Paid on', formatFeeDate(date)),
        ('Paid via', via),
        if (reference.isNotEmpty) ('Reference', reference),
      ],
      headers: const [],
      rows: const [],
      fileStem: 'receipt_${title}_${date.toIso8601String().substring(0, 10)}',
      sheetName: 'Receipt',
    ),
    ReportFormat.pdf,
  );
}

/// The receipt card for an already-paid fee: amount, date, how it was paid, and a download.
Future<void> showFeeReceipt({
  required BuildContext context,
  required String title,
  required String subtitle,
  required num amount,
  required DateTime? paidOn,
  required String via,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final palette = dialogContext.palette;
      Widget row(String k, String v, {bool strong = false}) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(k, style: TextStyle(fontSize: 11.5, fontWeight: AppType.semi, color: palette.textMuted)),
              Text(v,
                  style: TextStyle(
                      fontSize: strong ? 15 : 12,
                      fontWeight: strong ? AppType.heavy : AppType.bold,
                      color: palette.text)),
            ]),
          );
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: AppRadii.all(AppRadii.x4l),
            boxShadow: AppShadows.dialog,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: palette.paidManualSoft, borderRadius: AppRadii.all(13)),
                child: Icon(Icons.receipt_long_outlined, size: 18, color: palette.paidManual),
              ),
              Pressable(
                onTap: () => Navigator.of(dialogContext).pop(),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: palette.bg,
                    borderRadius: AppRadii.all(AppRadii.sm),
                    border: Border.all(color: palette.border),
                  ),
                  child: Icon(Icons.close, size: 13, color: palette.textMuted),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 15, fontWeight: AppType.heavy, color: palette.text)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11, color: palette.textFaint)),
            ],
            const SizedBox(height: 14),
            row('Amount paid', money(amount), strong: true),
            row('Paid on', paidOn == null ? '—' : formatFeeDate(paidOn)),
            row('Paid via', via),
            const SizedBox(height: 8),
            Pressable(
              onTap: () async {
                try {
                  await downloadReceiptPdf(
                      title: title, subtitle: subtitle, amount: amount, via: via, date: paidOn ?? DateTime.now());
                  if (dialogContext.mounted) showAppToast(dialogContext, 'Receipt PDF ready to save');
                } catch (_) {
                  if (dialogContext.mounted) showAppToast(dialogContext, "Couldn't create the receipt", error: true);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: palette.primary, borderRadius: AppRadii.all(AppRadii.lg)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.download_outlined, size: 14, color: palette.onPrimary),
                  const SizedBox(width: 6),
                  Text('Download receipt',
                      style: TextStyle(fontSize: 13, fontWeight: AppType.bold, color: palette.onPrimary)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Pressable(
              onTap: () => Navigator.of(dialogContext).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: AppRadii.all(AppRadii.lg),
                  border: Border.all(color: palette.border),
                ),
                child: Text('Close', style: TextStyle(fontSize: 13, fontWeight: AppType.bold, color: palette.text)),
              ),
            ),
          ]),
        ),
      );
    },
  );
}

enum _Step { amount, method, processing, success }

class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.title, required this.subtitle, required this.amount, required this.onPay});
  final String title;
  final String subtitle;
  final num amount;
  final Future<String> Function(String method) onPay;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  _Step _step = _Step.amount;
  String? _method;
  String _ref = '';
  String? _error;

  Future<void> _pay() async {
    setState(() {
      _step = _Step.processing;
      _error = null;
    });
    try {
      final ref = await widget.onPay(_method!);
      if (!mounted) return;
      setState(() {
        _ref = ref;
        _step = _Step.success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _step = _Step.method;
      });
    }
  }

  Widget _tile(IconData icon, VoidCallback onTap) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: AppRadii.all(9),
          border: Border.all(color: palette.border),
        ),
        child: Icon(icon, size: 14, color: palette.textMuted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final busy = _step == _Step.processing || _step == _Step.success;
    return PopScope(
      canPop: _step != _Step.processing,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _step == _Step.method
                    ? _tile(Icons.arrow_back, () => setState(() => _step = _Step.amount))
                    : const SizedBox(width: 28),
                Text(
                  switch (_step) {
                    _Step.amount => 'Pay fee',
                    _Step.method => 'Choose payment method',
                    _Step.processing => 'Processing',
                    _Step.success => 'Payment successful',
                  },
                  style: TextStyle(fontSize: 13.5, fontWeight: AppType.heavy, color: palette.text),
                ),
                busy ? const SizedBox(width: 28) : _tile(Icons.close, () => Navigator.of(context).pop(false)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              child: switch (_step) {
                _Step.amount => _amountStep(palette),
                _Step.method => _methodStep(palette),
                _Step.processing => _processingStep(palette),
                _Step.success => _successStep(palette),
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback? onTap, {double fontSize = 13.5, double vPad = 13}) {
    final palette = context.palette;
    final enabled = onTap != null;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: vPad),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? palette.primary : palette.surfaceHigh,
          borderRadius: AppRadii.all(13),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: fontSize, fontWeight: AppType.bold, color: enabled ? palette.onPrimary : palette.textFaint)),
      ),
    );
  }

  Widget _note(IconData icon, String text) {
    final palette = context.palette;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 11, color: palette.textFaint),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 9.5, color: palette.textFaint)),
    ]);
  }

  Widget _amountStep(AppPalette palette) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: AppRadii.all(AppRadii.xl),
          border: Border.all(color: palette.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: TextStyle(fontSize: 13, fontWeight: AppType.bold, color: palette.text)),
          if (widget.subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(widget.subtitle, style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
          ],
          const SizedBox(height: 10),
          Container(height: 1, color: palette.borderSoft),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Balance due', style: TextStyle(fontSize: 11, fontWeight: AppType.semi, color: palette.textMuted)),
            Text(money(widget.amount), style: TextStyle(fontSize: 14, fontWeight: AppType.heavy, color: palette.notPaid)),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      _note(Icons.lock_outline, 'This fee is collected in full, in one payment'),
      const SizedBox(height: 16),
      _primaryButton('Pay ${money(widget.amount)}', () => setState(() => _step = _Step.method)),
    ]);
  }

  Widget _methodStep(AppPalette palette) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: palette.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Amount to pay', style: TextStyle(fontSize: 11, fontWeight: AppType.semi, color: palette.textMuted)),
          Text(money(widget.amount), style: TextStyle(fontSize: 15, fontWeight: AppType.heavy, color: palette.text)),
        ]),
      ),
      const SizedBox(height: 16),
      for (final m in _methods)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Pressable(
            onTap: () => setState(() => _method = m.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _method == m.key ? palette.primarySoft : palette.surfaceRaised,
                borderRadius: AppRadii.all(13),
                border: Border.all(color: _method == m.key ? palette.primary : palette.border, width: 1.5),
              ),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _method == m.key ? palette.primary : palette.surfaceHigh,
                    borderRadius: AppRadii.all(11),
                  ),
                  child: Icon(m.icon, size: 16, color: _method == m.key ? palette.onPrimary : palette.textMuted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.label, style: TextStyle(fontSize: 12.5, fontWeight: AppType.bold, color: palette.text)),
                    const SizedBox(height: 1),
                    Text(m.sub, style: TextStyle(fontSize: 10, color: palette.textFaint)),
                  ]),
                ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _method == m.key ? palette.primary : Colors.transparent,
                    border: Border.all(color: _method == m.key ? palette.primary : palette.border, width: 1.5),
                  ),
                  child: _method == m.key ? Icon(Icons.check, size: 11, color: palette.onPrimary) : null,
                ),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 8),
      _note(Icons.lock_outline, 'Secured, encrypted payment'),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: palette.notPaid)),
        ),
      const SizedBox(height: 16),
      _primaryButton('Pay ${money(widget.amount)}', _method == null ? null : _pay),
    ]);
  }

  Widget _processingStep(AppPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 36, 0, 24),
        child: Column(children: [
          SizedBox(width: 38, height: 38, child: CircularProgressIndicator(strokeWidth: 3, color: palette.primary)),
          const SizedBox(height: 14),
          Text('Confirming your payment…', style: TextStyle(fontSize: 13, fontWeight: AppType.bold, color: palette.text)),
          const SizedBox(height: 14),
          Text("Please don't close this screen", style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
        ]),
      );

  Widget _successStep(AppPalette palette) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 14),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: palette.paidManualSoft, shape: BoxShape.circle),
            child: Icon(Icons.check_circle_outline, size: 34, color: palette.paidManual),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text('${money(widget.amount)} paid',
              style: TextStyle(fontSize: 16, fontWeight: AppType.heavy, color: palette.text)),
        ),
        const SizedBox(height: 3),
        Center(child: Text(widget.title, style: TextStyle(fontSize: 11, color: palette.textFaint))),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: palette.surfaceHigh,
            borderRadius: AppRadii.all(AppRadii.lg),
            border: Border.all(color: palette.border),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Transaction ID', style: TextStyle(fontSize: 10.5, fontWeight: AppType.semi, color: palette.textMuted)),
            Text(_ref, style: TextStyle(fontSize: 11.5, fontWeight: AppType.bold, fontFamily: 'monospace', color: palette.text)),
          ]),
        ),
        const SizedBox(height: 14),
        Pressable(
          onTap: () async {
            try {
              await downloadReceiptPdf(
                title: widget.title,
                subtitle: widget.subtitle,
                amount: widget.amount,
                via: 'Online payment',
                date: DateTime.now(),
                reference: _ref,
              );
            } catch (_) {
              if (mounted) showAppToast(context, "Couldn't create the receipt", error: true);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: AppRadii.all(13),
              border: Border.all(color: palette.border),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.download_outlined, size: 14, color: palette.textMuted),
              const SizedBox(width: 6),
              Text('Download receipt', style: TextStyle(fontSize: 12.5, fontWeight: AppType.bold, color: palette.text)),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        _primaryButton('Done', () => Navigator.of(context).pop(true)),
      ]);
}
