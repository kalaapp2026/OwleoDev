import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/sections.dart';
import '../plans/plans_screen.dart';
import 'bill_widgets.dart';
import 'collections_data.dart';

/// Shared plumbing for the Collections dialogs: a busy flag, an error line and a guarded submit.
mixin _Submit<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String? error;
  bool busy = false;

  Future<void> submit(Future<void> Function() job) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await job();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.message;
        });
      }
    }
  }

  void fail(String msg) => setState(() => error = msg);
}

final _money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))];

// ---------------------------------------------------------------------------------------------

/// Reminds an academy about one or more unpaid bills.
class RemindModal extends ConsumerStatefulWidget {
  const RemindModal({super.key, required this.academy, required this.bills});
  final Map<String, dynamic> academy;
  final List<Map<String, dynamic>> bills;

  @override
  ConsumerState<RemindModal> createState() => _RemindModalState();
}

class _RemindModalState extends ConsumerState<RemindModal> with _Submit {
  late final _msg = TextEditingController(text: _draft());

  String _draft() {
    final a = widget.academy;
    final first = (a.strOrNull('owner_name') ?? 'there').split(' ').first;
    final bills = widget.bills;
    final total = bills.fold<double>(0, (s, b) => s + b.number('balance'));
    final over = bills.where((b) => b.str('status') == 'overdue').toList();
    if (bills.length == 1) {
      final b = bills.first;
      final when = b.str('status') == 'overdue' ? 'was due on ${fdShort(b['dueOn'])} and is ${b.integer('daysLate')} days overdue' : 'is due on ${fdShort(b['dueOn'])}';
      return 'Hi $first, this is Owleo. Your ${monthLong(b.str('period'))} bill ${b.str('number')} of ${inr(total)} $when. You can pay from Billing in your Owleo Nest app. Thank you!';
    }
    return 'Hi $first, this is Owleo. ${a.str('name')} has ${bills.length} unpaid bills totalling ${inr(total)}${over.isEmpty ? '' : ', of which ${inr(over.fold<double>(0, (s, b) => s + b.number('balance')))} is overdue'}. You can pay from Billing in your Owleo Nest app. Thank you!';
  }

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.academy;
    return ModalFrame(
      title: 'Send a reminder',
      sub: a.str('name'),
      error: error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Send', kind: BtnKind.primary, busy: busy, onPressed: () {
          if (_msg.text.trim().length < 10) return fail('Write a short message.');
          submit(() async {
            await ref.read(dioClientProvider).postMap('/admin/hq/collections/academies/${a.str('id')}/remind',
                body: {'invoiceIds': [for (final b in widget.bills) b.str('id')], 'channels': 'In-app', 'message': _msg.text.trim()});
          });
        }),
      ],
      children: [
        Text('To ${a.str('owner_name', 'the academy admins')} and the other admins of this academy', style: HqText.muted.copyWith(fontSize: 12.5)),
        const SizedBox(height: 4),
        Text('Delivered in their Owleo Nest app, in the notifications bell.', style: HqText.sub),
        const SizedBox(height: 12),
        HqField(label: 'Message', controller: _msg, maxLines: 5),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------

class PaymentModal extends ConsumerStatefulWidget {
  const PaymentModal({super.key, required this.bill, required this.academyName});
  final Map<String, dynamic> bill;
  final String academyName;

  @override
  ConsumerState<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends ConsumerState<PaymentModal> with _Submit {
  late final _amount = TextEditingController(text: widget.bill.number('balance').round().toString());
  final _ref = TextEditingController();
  String _mode = 'Bank transfer';
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final balance = b.number('balance');
    return ModalFrame(
      title: 'Record a payment',
      sub: '${widget.academyName} · ${b.str('number')}',
      error: error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Save payment', kind: BtnKind.primary, busy: busy, onPressed: () {
          final amt = double.tryParse(_amount.text.replaceAll(',', ''));
          if (amt == null || amt <= 0) return fail('Enter the amount received.');
          if (amt > balance + 0.5) return fail('That is more than the ${inr(balance)} still to pay.');
          submit(() async {
            await ref.read(dioClientProvider).postMap('/admin/hq/collections/bills/${b.str('id')}/payments',
                body: {'amount': amt, 'mode': _mode, 'reference': _ref.text.trim(), 'paidOn': _date.toIso8601String().substring(0, 10)});
          });
        }),
      ],
      children: [
        HqField(label: 'Amount received (₹)', controller: _amount, keyboard: TextInputType.number, formatters: _money),
        HqSelect<String>(
          label: 'How it was paid',
          value: _mode,
          searchable: false,
          options: [for (final m in const ['UPI', 'Bank transfer', 'Cheque', 'Cash', 'Card', 'Net banking', 'Autopay']) SelectOption(m, m)],
          onChanged: (v) => setState(() => _mode = v),
        ),
        HqField(label: 'Reference or UTR', controller: _ref, hint: 'Bank reference, cheque number or receipt'),
        DateButton(
          label: 'Date received',
          value: _date,
          onTap: () async {
            final d = await pickHqDate(context, initial: _date, first: toDate(b['issuedOn']), last: DateTime.now());
            if (d != null) setState(() => _date = d);
          },
        ),
        Text('To pay now: ${inr(balance)}. A smaller amount is saved as a part payment.', style: HqText.sub),
        const SizedBox(height: 12),
      ],
    );
  }
}

class AdjustModal extends ConsumerStatefulWidget {
  const AdjustModal({super.key, required this.bill});
  final Map<String, dynamic> bill;

  @override
  ConsumerState<AdjustModal> createState() => _AdjustModalState();
}

class _AdjustModalState extends ConsumerState<AdjustModal> with _Submit {
  final _desc = TextEditingController();
  final _amount = TextEditingController();
  String _type = 'charge';
  String _category = 'adjustment';

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ModalFrame(
      title: 'Add a charge or credit',
      sub: widget.bill.str('number'),
      error: error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Add', kind: BtnKind.primary, busy: busy, onPressed: () {
          final amt = double.tryParse(_amount.text.replaceAll(',', ''));
          if (_desc.text.trim().length < 3) return fail('Say what it is for.');
          if (amt == null || amt <= 0) return fail('Enter the amount.');
          submit(() async {
            await ref.read(dioClientProvider).postMap('/admin/hq/collections/bills/${widget.bill.str('id')}/adjustments',
                body: {'description': _desc.text.trim(), 'type': _type, 'category': _category, 'amount': amt});
          });
        }),
      ],
      children: [
        HqField(label: 'What is it for', controller: _desc, hint: 'For example: Setup help, or Goodwill credit'),
        HqSelect<String>(
          label: 'Type',
          value: _type,
          searchable: false,
          options: const [SelectOption('charge', 'Charge (adds to the bill)'), SelectOption('credit', 'Credit (takes off the bill)')],
          onChanged: (v) => setState(() => _type = v),
        ),
        HqSelect<String>(
          label: 'Counts as revenue from',
          value: _category,
          searchable: false,
          options: const [SelectOption('adjustment', 'Platform fees (credits and other)'), SelectOption('marketing', 'Marketing fees'), SelectOption('commission', 'Other service fees (event commission)')],
          onChanged: (v) => setState(() => _category = v),
        ),
        HqField(label: 'Amount (₹)', controller: _amount, keyboard: TextInputType.number, formatters: _money),
        Text('GST is worked out again on the new total.', style: HqText.sub),
        const SizedBox(height: 12),
      ],
    );
  }
}

class DueDateModal extends ConsumerStatefulWidget {
  const DueDateModal({super.key, required this.bill});
  final Map<String, dynamic> bill;

  @override
  ConsumerState<DueDateModal> createState() => _DueDateModalState();
}

class _DueDateModalState extends ConsumerState<DueDateModal> with _Submit {
  late DateTime _due = toDate(widget.bill['dueOn']) ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final cur = toDate(widget.bill['dueOn']) ?? DateTime.now();
    return ModalFrame(
      title: 'Change the due date',
      sub: '${widget.bill.str('number')} · now ${fd(cur)}',
      error: error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Save', kind: BtnKind.primary, busy: busy, onPressed: () {
          submit(() async {
            await ref.read(dioClientProvider).putMap('/admin/hq/collections/bills/${widget.bill.str('id')}/due', body: {'dueOn': _due.toIso8601String().substring(0, 10)});
          });
        }),
      ],
      children: [
        DateButton(
          label: 'New due date',
          value: _due,
          onTap: () async {
            final d = await pickHqDate(context, initial: _due, first: toDate(widget.bill['issuedOn']), last: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => _due = d);
          },
        ),
        ChipRow([for (final n in const [7, 15, 30]) HqChip('+$n days', selected: false, onTap: () => setState(() => _due = cur.add(Duration(days: n))))]),
        const SizedBox(height: 14),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------

class OfferModal extends ConsumerStatefulWidget {
  const OfferModal({super.key, this.offer});
  final Map<String, dynamic>? offer;

  @override
  ConsumerState<OfferModal> createState() => _OfferModalState();
}

class _OfferModalState extends ConsumerState<OfferModal> with _Submit {
  late final _name = TextEditingController(text: widget.offer?.str('name') ?? '');
  late final _code = TextEditingController(text: widget.offer?.str('code') ?? '');
  late final _value = TextEditingController(text: widget.offer == null || widget.offer!.str('type') == 'free' ? '' : widget.offer!.number('value').round().toString());
  late final _limit = TextEditingController(text: widget.offer?.integerOrNull('limit')?.toString() ?? '');
  late String _type = widget.offer?.str('type', 'pct') ?? 'pct';
  late String _applies = widget.offer?.str('appliesTo', 'all') ?? 'all';
  late DateTime _from = toDate(widget.offer?['startsOn']) ?? DateTime.now();
  late DateTime _to = toDate(widget.offer?['endsOn']) ?? DateTime.now().add(const Duration(days: 60));

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _value.dispose();
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(plansProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final editing = widget.offer != null;
    return ModalFrame(
      title: editing ? 'Edit offer' : 'New offer',
      error: error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Save offer', kind: BtnKind.primary, busy: busy, onPressed: () {
          if (_name.text.trim().length < 3) return fail('Give the offer a name.');
          if (!RegExp(r'^[A-Za-z0-9]{4,14}$').hasMatch(_code.text.trim())) return fail('The code needs 4 to 14 letters or numbers.');
          if (_to.isBefore(_from)) return fail('The end date must be after the start date.');
          submit(() async {
            final body = {
              'name': _name.text.trim(), 'code': _code.text.trim().toUpperCase(), 'type': _type, 'value': _value.text.trim(),
              'appliesTo': _applies, 'startsOn': _from.toIso8601String().substring(0, 10), 'endsOn': _to.toIso8601String().substring(0, 10), 'limit': _limit.text.trim(),
            };
            final dio = ref.read(dioClientProvider);
            if (editing) {
              await dio.putMap('/admin/hq/collections/offers/${widget.offer!.str('id')}', body: body);
            } else {
              await dio.postMap('/admin/hq/collections/offers', body: body);
            }
          });
        }),
      ],
      children: [
        HqField(label: 'Offer name', controller: _name),
        HqField(label: 'Code', controller: _code, maxLength: 14, formatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')), UpperCaseFormatter()]),
        HqSelect<String>(
          label: 'Discount',
          value: _type,
          searchable: false,
          options: const [SelectOption('pct', 'Percent off'), SelectOption('flat', 'Fixed amount off'), SelectOption('free', 'First month free')],
          onChanged: (v) => setState(() => _type = v),
        ),
        if (_type != 'free') HqField(label: _type == 'pct' ? 'Percent' : 'Amount (₹)', controller: _value, keyboard: TextInputType.number, formatters: _money),
        HqSelect<String>(
          label: 'Who can use it',
          value: _applies,
          options: [const SelectOption('all', 'All plans'), for (final p in plans) SelectOption(p.str('code'), '${p.str('name')} plan')],
          onChanged: (v) => setState(() => _applies = v),
        ),
        FieldRow([
          DateButton(label: 'Starts', value: _from, onTap: () async {
            final d = await pickHqDate(context, initial: _from, first: DateTime(2024), last: DateTime(2035));
            if (d != null) setState(() => _from = d);
          }),
          DateButton(label: 'Ends', value: _to, onTap: () async {
            final d = await pickHqDate(context, initial: _to, first: DateTime(2024), last: DateTime(2035));
            if (d != null) setState(() => _to = d);
          }),
        ]),
        HqField(label: 'Use limit (optional)', controller: _limit, hint: 'No limit', keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly]),
      ],
    );
  }
}

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => newValue.copyWith(text: newValue.text.toUpperCase());
}

class AddonModal extends ConsumerStatefulWidget {
  const AddonModal({super.key, this.addon});
  final Map<String, dynamic>? addon;

  @override
  ConsumerState<AddonModal> createState() => _AddonModalState();
}

class _AddonModalState extends ConsumerState<AddonModal> with _Submit {
  late final _name = TextEditingController(text: widget.addon?.str('name') ?? '');
  late final _desc = TextEditingController(text: widget.addon?.str('description') ?? '');
  late final _price = TextEditingController(text: widget.addon == null ? '' : widget.addon!.number('price').round().toString());
  late String _billing = widget.addon?.str('billing', 'month') ?? 'month';

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.addon != null;
    return ModalFrame(
      title: editing ? 'Edit add-on' : 'New add-on',
      error: error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Save add-on', kind: BtnKind.primary, busy: busy, onPressed: () {
          final p = double.tryParse(_price.text.replaceAll(',', ''));
          if (_name.text.trim().length < 3) return fail('Give it a name.');
          if (_desc.text.trim().length < 5) return fail('Say what the academy gets.');
          if (p == null || p <= 0) return fail('Enter the price.');
          submit(() async {
            final body = {'name': _name.text.trim(), 'description': _desc.text.trim(), 'price': p, 'billing': _billing};
            final dio = ref.read(dioClientProvider);
            if (editing) {
              await dio.putMap('/admin/hq/collections/addons/${widget.addon!.str('id')}', body: body);
            } else {
              await dio.postMap('/admin/hq/collections/addons', body: body);
            }
          });
        }),
      ],
      children: [
        HqField(label: 'Name', controller: _name),
        HqField(label: 'What the academy gets', controller: _desc),
        HqField(label: 'Price (₹)', controller: _price, keyboard: TextInputType.number, formatters: _money),
        HqSelect<String>(
          label: 'Billed',
          value: _billing,
          searchable: false,
          options: const [SelectOption('month', 'Every month'), SelectOption('one_time', 'One time')],
          onChanged: (v) => setState(() => _billing = v),
        ),
        Text('A new price applies from the next bill.', style: HqText.sub),
        const SizedBox(height: 12),
      ],
    );
  }
}

class AssignAddonModal extends ConsumerStatefulWidget {
  const AssignAddonModal({super.key, required this.academyId, required this.academyName});
  final String academyId, academyName;

  @override
  ConsumerState<AssignAddonModal> createState() => _AssignAddonModalState();
}

class _AssignAddonModalState extends ConsumerState<AssignAddonModal> with _Submit {
  String? _addon;

  @override
  Widget build(BuildContext context) {
    final addons = (ref.watch(addonsProvider).valueOrNull ?? const <Map<String, dynamic>>[]).where((a) => a.flag('onSale')).toList();
    return ModalFrame(
      title: 'Add an add-on',
      sub: '${widget.academyName} · starts from the next bill',
      error: error,
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        HqButton('Add', kind: BtnKind.primary, busy: busy, onPressed: () {
          if (_addon == null) return fail('Choose an add-on.');
          submit(() async {
            await ref.read(dioClientProvider).postMap('/admin/hq/collections/academies/${widget.academyId}/addons', body: {'addonId': _addon});
          });
        }),
      ],
      children: [
        HqSelect<String>(
          label: 'Add-on',
          value: _addon,
          hint: 'Choose an add-on',
          options: [for (final a in addons) SelectOption(a.str('id'), '${a.str('name')} · ${inr(a.number('price'))}${a.str('billing') == 'month' ? ' / month' : ''}')],
          onChanged: (v) => setState(() => _addon = v),
        ),
      ],
    );
  }
}
