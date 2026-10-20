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
import '../../core/ui/primitives.dart';
import '../../core/ui/sections.dart';
import '../academies/academy_form.dart';
import '../plans/plans_screen.dart';
import 'onboarding_screen.dart';

/// Opens the full-screen Add academy form. On success the new lead appears in the pipeline.
Future<void> showAddAcademy(BuildContext context, WidgetRef ref) async {
  final done = await showHqFullPage<bool>(context, builder: (_) => const AddAcademyPage());
  if (done == true) {
    ref.invalidate(onboardingProvider);
    if (context.mounted) showToast(context, 'Added to Onboarding as a lead');
  }
}

const _banks = ['HDFC Bank', 'ICICI Bank', 'State Bank of India', 'Axis Bank', 'Kotak Mahindra Bank', 'Canara Bank', 'Bank of Baroda', 'Other'];

class _Acct {
  String bank = 'HDFC Bank';
  String type = 'Current';
  String gw = 'Razorpay';
  final holder = TextEditingController();
  final acct = TextEditingController();
  final ifsc = TextEditingController();

  bool get any => holder.text.trim().isNotEmpty || acct.text.trim().isNotEmpty || ifsc.text.trim().isNotEmpty;
  bool get ok => holder.text.trim().length >= 3 && RegExp(r'^\d{9,18}$').hasMatch(acct.text.trim()) && RegExp(r'^[A-Za-z]{4}0[A-Za-z0-9]{6}$').hasMatch(ifsc.text.trim());

  Map<String, dynamic> toJson() => {'bank': bank, 'type': type, 'gw': gw, 'holder': holder.text.trim(), 'acct': acct.text.trim(), 'ifsc': ifsc.text.trim()};

  void dispose() {
    holder.dispose();
    acct.dispose();
    ifsc.dispose();
  }
}

class AddAcademyPage extends ConsumerStatefulWidget {
  const AddAcademyPage({super.key});

  @override
  ConsumerState<AddAcademyPage> createState() => _AddAcademyPageState();
}

class _AddAcademyPageState extends ConsumerState<AddAcademyPage> {
  final AcademyFormData _data = AcademyFormData();
  final List<_Acct> _accts = [_Acct(), _Acct()];
  int _shown = 1;
  int _primary = 0;
  String? _plan;
  final _est = TextEditingController();
  String _months = '2';
  final Set<String> _open = {'details'};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final a in _accts) {
      for (final c in [a.holder, a.acct, a.ifsc]) {
        c.addListener(() => setState(() {}));
      }
    }
    _est.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _data.dispose();
    for (final a in _accts) {
      a.dispose();
    }
    _est.dispose();
    super.dispose();
  }

  List<(String, String)> _issues() {
    final out = [..._data.issues()];
    final a0 = _accts[0];
    if (!a0.ok) out.add(('bank', 'Add the first bank account: holder name, 9 to 18 digit number and IFSC.'));
    if (_shown > 1 && _accts[1].any && !_accts[1].ok) out.add(('bank', 'Finish bank account 2 or clear it.'));
    final nums = [for (var i = 0; i < _shown; i++) if (_accts[i].ok) _accts[i].acct.text.trim()];
    if (nums.toSet().length < nums.length) out.add(('bank', 'The same account number is used twice.'));
    if (_plan == null) out.add(('plan', 'Choose a plan.'));
    if ((int.tryParse(_est.text.trim()) ?? 0) <= 0) out.add(('plan', 'Enter the expected number of students.'));
    return out;
  }

  Future<void> _submit() async {
    final issues = _issues();
    if (issues.isNotEmpty) {
      setState(() => _open.add(issues.first.$1));
      showToast(context, issues.first.$2);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/onboarding/leads', body: {
        ..._data.toJson(),
        'plan': _plan,
        'est': int.parse(_est.text.trim()),
        'months': int.parse(_months),
        'accts': [for (var i = 0; i < _shown; i++) _accts[i].toJson()],
        'primary': _primary,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(plansProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final issues = _issues();
    bool ok(String s) => !issues.any((i) => i.$1 == s);
    final nOk = [for (var i = 0; i < _shown; i++) if (_accts[i].ok) i].length;
    void toggle(String k) => setState(() => _open.contains(k) ? _open.remove(k) : _open.add(k));
    final plan = plans.where((p) => p.str('code') == _plan).firstOrNull;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListenableBuilder(
          listenable: _data,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FormTopBar(title: 'Add academy', subtitle: 'Create an academy profile', onBack: () => Navigator.of(context).pop()),
              AcademyFormSections(data: _data, open: _open, onToggle: toggle),
              CollapsibleSection(
                icon: 'bank',
                title: 'Bank accounts',
                summary: 'Where fees are paid out',
                open: _open.contains('bank'),
                onToggle: () => toggle('bank'),
                badge: ok('bank') ? '$nOk account${nOk == 1 ? '' : 's'}' : 'Incomplete',
                badgeTone: ok('bank') ? Tone.green : Tone.gold,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < _shown; i++) _acctCard(i),
                  if (_shown < 2)
                    HqButton('Add another bank account', icon: 'plus', expand: true, onPressed: () => setState(() => _shown = 2))
                  else
                    Center(child: Text('Up to 2 bank accounts, each mapped to one payment gateway.', style: HqText.sub)),
                  Padding(padding: const EdgeInsets.fromLTRB(2, 10, 2, 12), child: Text('Account numbers are shown masked after saving.', style: HqText.sub)),
                ]),
              ),
              CollapsibleSection(
                icon: 'rocket',
                title: 'Plan and demo',
                summary: '${plan?.str('name') ?? 'Choose a plan'} · $_months-month demo',
                open: _open.contains('plan'),
                onToggle: () => toggle('plan'),
                badge: ok('plan') ? 'Done' : 'Incomplete',
                badgeTone: ok('plan') ? Tone.green : Tone.gold,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FieldRow([
                    HqSelect<String>(
                      label: 'Plan',
                      value: _plan,
                      hint: 'Choose a plan',
                      options: [for (final p in plans) SelectOption(p.str('code'), '${p.str('name')} · ${inr(p.number('price'))}/mo')],
                      onChanged: (v) => setState(() => _plan = v),
                    ),
                    HqField(label: 'Expected students', controller: _est, hint: 'e.g. 150', keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly]),
                  ]),
                  HqSelect<String>(
                    label: 'Demo period',
                    value: _months,
                    searchable: false,
                    options: const [SelectOption('2', '2 months'), SelectOption('3', '3 months')],
                    onChanged: (v) => setState(() => _months = v),
                  ),
                ]),
              ),
              HqButton('Create academy', icon: 'check', kind: BtnKind.primary, expand: true, busy: _busy, onPressed: issues.isEmpty ? _submit : null),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: issues.isEmpty ? null : () => setState(() => _open.add(issues.first.$1)),
                    child: Text(issues.isEmpty ? 'Ready to add to onboarding.' : issues.first.$2, textAlign: TextAlign.center, style: HqText.muted),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _acctCard(int i) {
    final a = _accts[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Hq.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Hq.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Account ${i + 1} · ${i == 0 ? 'Required' : 'Optional'}', style: HqText.row)),
          if (_primary == i)
            const Tag('Primary payout', tone: Tone.primary)
          else
            HqButton('Make primary', small: true, onPressed: () => setState(() => _primary = i)),
          if (i > 0) ...[
            const SizedBox(width: 6),
            HqIconButton('trash', size: 32, onTap: () => setState(() {
                  _shown = 1;
                  _primary = 0;
                  a.holder.clear();
                  a.acct.clear();
                  a.ifsc.clear();
                })),
          ],
        ]),
        const SizedBox(height: 12),
        HqSelect<String>(label: 'Bank', value: a.bank, options: [for (final b in _banks) SelectOption(b, b)], onChanged: (v) => setState(() => a.bank = v)),
        HqSelect<String>(label: 'Payment gateway for this account', value: a.gw, searchable: false, options: [for (final g in const ['Razorpay', 'Cashfree', 'PayU']) SelectOption(g, g)], onChanged: (v) => setState(() => a.gw = v)),
        FieldRow([
          HqField(label: 'Account holder', controller: a.holder, hint: 'Name on the account'),
          HqSelect<String>(label: 'Account type', value: a.type, searchable: false, options: const [SelectOption('Current', 'Current'), SelectOption('Savings', 'Savings')], onChanged: (v) => setState(() => a.type = v)),
        ]),
        FieldRow([
          HqField(label: 'Account number', controller: a.acct, hint: '9 to 18 digits', keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)]),
          HqField(label: 'IFSC code', controller: a.ifsc, hint: 'e.g. HDFC0001234', formatters: [LengthLimitingTextInputFormatter(11)]),
        ]),
      ]),
    );
  }
}
