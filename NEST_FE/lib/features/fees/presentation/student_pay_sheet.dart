import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:share_plus/share_plus.dart';

const _methods = [
  (key: 'UPI', label: 'UPI', sub: 'Google Pay, PhonePe, Paytm', icon: Icons.smartphone_outlined),
  (key: 'CARD', label: 'Credit / Debit Card', sub: 'Visa, Mastercard, RuPay', icon: Icons.credit_card_outlined),
  (key: 'NETBANKING', label: 'Netbanking', sub: 'All major banks', icon: Icons.account_balance_outlined),
];

/// The student's pay flow: confirm the amount, pick a method, pay, then a success screen with a
/// reference and a receipt to share. [onPay] performs the payment and returns its reference; the
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

/// A plain-text receipt, shared through the platform sheet (a save dialog on web).
Future<void> shareReceipt({
  required String title,
  required String detail,
  required num amount,
  required String reference,
  required String mode,
  required DateTime date,
}) {
  final text = [
    'Owleo N.E.S.T. - Payment receipt',
    '',
    'Fee: $title',
    if (detail.isNotEmpty) 'Details: $detail',
    'Amount paid: ${money(amount)}',
    'Paid via: $mode',
    if (reference.isNotEmpty) 'Reference: $reference',
    'Date: ${formatFeeDate(date)}',
  ].join('\n');
  return Share.shareXFiles([
    XFile.fromData(Uint8List.fromList(utf8.encode(text)), name: 'receipt.txt', mimeType: 'text/plain'),
  ], text: 'Receipt for $title');
}

enum _Step { method, processing, success }

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
  _Step _step = _Step.method;
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopScope(
      canPop: _step != _Step.processing,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              switch (_step) {
                _Step.method => 'Pay fee',
                _Step.processing => 'Processing',
                _Step.success => 'Payment successful',
              },
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.text),
            ),
            const SizedBox(height: 14),
            if (_step == _Step.method) ..._methodStep(palette),
            if (_step == _Step.processing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Column(children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text('Confirming your payment…', style: TextStyle(fontWeight: FontWeight.w700, color: palette.text)),
                  const SizedBox(height: 4),
                  Text("Please don't close this screen", style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
                ]),
              ),
            if (_step == _Step.success) ..._successStep(palette),
          ]),
        ),
      ),
    );
  }

  List<Widget> _methodStep(AppPalette palette) => [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surfaceHigh,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: palette.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.text)),
            if (widget.subtitle.isNotEmpty)
              Text(widget.subtitle, style: TextStyle(fontSize: 10.5, color: palette.textFaint)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Balance due', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.textMuted)),
              Text(money(widget.amount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.notPaid)),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        for (final m in _methods)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: AppRadii.all(AppRadii.xl),
              onTap: () => setState(() => _method = m.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _method == m.key ? palette.primarySoft : palette.surfaceRaised,
                  borderRadius: AppRadii.all(AppRadii.xl),
                  border: Border.all(color: _method == m.key ? palette.primary : palette.border, width: 1.5),
                ),
                child: Row(children: [
                  Icon(m.icon, size: 18, color: _method == m.key ? palette.primary : palette.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.text)),
                      Text(m.sub, style: TextStyle(fontSize: 10, color: palette.textFaint)),
                    ]),
                  ),
                  if (_method == m.key) Icon(Icons.check_circle, size: 18, color: palette.primary),
                ]),
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(fontSize: 11.5, color: palette.notPaid)),
          ),
        FilledButton(
          onPressed: _method == null ? null : _pay,
          child: Text('Pay ${money(widget.amount)}'),
        ),
      ];

  List<Widget> _successStep(AppPalette palette) => [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: palette.paidManualSoft, shape: BoxShape.circle),
            child: Icon(Icons.check_circle_outline, size: 34, color: palette.paidManual),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text('${money(widget.amount)} paid',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.text)),
        ),
        const SizedBox(height: 4),
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
            Text('Reference', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: palette.textMuted)),
            Text(_ref, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: palette.text)),
          ]),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.download, size: 15),
          label: const Text('Download receipt'),
          onPressed: () => shareReceipt(
            title: widget.title,
            detail: widget.subtitle,
            amount: widget.amount,
            reference: _ref,
            mode: 'Online payment',
            date: DateTime.now(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Done')),
      ];
}
