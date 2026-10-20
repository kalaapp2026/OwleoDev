import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/ui/async.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../academies/academies_screen.dart';
import '../academies/academy_meta.dart';
import '../approvals/approvals_screen.dart';
import '../shell/nav.dart';

final onboardingProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(dioClientProvider).getMap('/admin/hq/onboarding'),
);

/// Onboarding: new academies from first conversation, through a demo, to live.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _stage = 0;

  bool get _write => ref.read(sessionProvider).user?.canWrite ?? false;

  Future<void> _call(String path, String ok, {bool showCreds = false}) async {
    try {
      final r = await ref.read(dioClientProvider).postMap(path);
      ref.invalidate(onboardingProvider);
      ref.invalidate(academiesProvider);
      ref.invalidate(approvalsProvider);
      if (!mounted) return;
      if (showCreds) {
        await showHqModal<void>(context, width: 440, builder: (_) => _Credentials(username: r.str('username'), password: r.str('password')));
      } else {
        showToast(context, ok);
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(onboardingProvider);
    return asyncBody(data, onRetry: () => ref.invalidate(onboardingProvider), data: (d) {
      final leads = d.maps('leads'), demos = d.maps('demos'), live = d.maps('live');
      final running = demos.where((x) => !x.flag('demoDone')).toList();
      final ready = demos.where((x) => x.flag('demoDone')).toList();
      final counts = [leads.length, demos.length, live.length];
      final wide = MediaQuery.sizeOf(context).width >= 760;

      final cols = [
        _Col('Lead', leads.length, [for (final p in leads) _leadCard(p)]),
        _Col('Demo', demos.length, [
          _Sub('Current demo', running.length, Tone.blue),
          for (final p in running) _runningCard(p),
          if (running.isEmpty) const _None(),
          _Sub('Completed, ready to go live', ready.length, Tone.green),
          for (final p in ready) _readyCard(p),
          if (ready.isEmpty) const _None(),
        ]),
        _Col('Live', live.length, [for (final p in live) _liveCard(p)]),
      ];

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HqGrid(GridKind.g4, [
          Kpi(icon: 'rocket', tone: Tone.violet, label: 'In pipeline', value: '${leads.length + demos.length}', foot: '${leads.length} leads · ${demos.length} demos'),
          Kpi(icon: 'clock', tone: Tone.blue, label: 'Demos running', value: '${running.length}', foot: '2 or 3 month demo period'),
          Kpi(icon: 'check', tone: Tone.green, label: 'Ready to go live', value: '${ready.length}', foot: 'demo completed'),
          Kpi(icon: 'rupee', tone: Tone.gold, label: 'Potential MRR', value: short(d.number('potentialMrr')), foot: 'if all go live on chosen plans'),
        ]),
        if (!wide)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              for (final (i, t) in const ['Lead', 'Demo', 'Live'].indexed)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() => _stage = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _stage == i ? Hq.tint(Hq.primary, .12) : Hq.raised,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _stage == i ? Hq.primary.withValues(alpha: .4) : Hq.border),
                          ),
                          child: Column(children: [
                            Text('${counts[i]}', style: HqText.h3.copyWith(fontSize: 16, color: _stage == i ? Hq.primary : Hq.text)),
                            Text(t, style: HqText.small.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: _stage == i ? Hq.primary : Hq.muted)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (i, c) in cols.indexed) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: _column(c))],
          ])
        else
          _column(cols[_stage]),
      ]);
    });
  }

  Widget _column(_Col c) => Container(
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(minHeight: 200),
        decoration: BoxDecoration(color: Hq.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Hq.soft)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(c.title, style: HqText.h3.copyWith(fontSize: 12.5)),
              Text('${c.count}', style: HqText.small.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
          if (c.children.isEmpty) const _None() else for (final w in c.children) Padding(padding: const EdgeInsets.only(bottom: 10), child: w),
        ]),
      );

  Widget _head(Map<String, dynamic> p) => Row(children: [
        Avatar(initials(p.str('name')), tone: AcademyMeta.typeTone(p.str('type')), square: true),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.str('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row),
            Text('${p.str('city')} · ${p.str('owner')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
          ]),
        ),
      ]);

  Widget _tags(Map<String, dynamic> p, {Widget? extra}) => Wrap(spacing: 6, runSpacing: 6, children: [
        if (p.strOrNull('planName') != null) Tag(p.str('planName'), tone: Tone.blue),
        Tag('~${p.integer('est')} students', tone: Tone.mute),
        ?extra,
      ]);

  Widget _card(List<Widget> children) => HqCard(
        radius: 14,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 9), children[i]]]),
      );

  Widget _leadCard(Map<String, dynamic> p) => _card([
        _head(p),
        _tags(p, extra: Tag('${p.integer('months')}-month demo', tone: Tone.violet)),
        if (_write) HqButton('Start ${p.integer('months')}-month demo', small: true, onPressed: () => _call('/admin/hq/onboarding/leads/${p.str('id')}/start-demo', '', showCreds: true)),
      ]);

  Widget _runningCard(Map<String, dynamic> p) {
    final tot = p.integer('months') * 30, left = p.integer('daysLeft'), low = left <= 14;
    return _card([
      _head(p),
      _tags(p),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${p.integer('months')}-month demo · day ${p.integer('dayIn')} of $tot', style: HqText.small.copyWith(fontSize: 12)),
          Text('$left days left', style: HqText.row.copyWith(fontSize: 12, color: low ? Hq.gold : Hq.text)),
        ]),
        const SizedBox(height: 6),
        HqBar(p.integer('dayIn') / tot * 100, tone: low ? Tone.gold : Tone.primary),
      ]),
      if (_write) HqButton('Mark demo complete', small: true, onPressed: () => _call('/admin/hq/onboarding/leads/${p.str('id')}/finish-demo', '${p.str('name')} demo marked complete. Ready to go live.')),
    ]);
  }

  Widget _readyCard(Map<String, dynamic> p) {
    final c = p.obj('checks');
    final approval = c.str('approval');
    final allOk = c.flag('details') && c.flag('gateway') && c.flag('approved');
    Widget step(bool ok, String title, String sub, Widget? btn) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Tag(ok ? '✓' : 'To do', tone: ok ? Tone.green : Tone.mute),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: HqText.row.copyWith(fontSize: 12.5)),
                Text(sub, style: HqText.small),
              ]),
            ),
            if (!ok && _write) ?btn,
          ]),
        );
    final id = p.str('id');
    return _card([
      _head(p),
      _tags(p, extra: Tag('${p.integer('months')}-month demo completed', tone: Tone.green)),
      Column(children: [
        step(c.flag('details'), 'Details validated', 'Required fields, duplicates and formats', HqButton('Validate', small: true, onPressed: () => _call('/admin/hq/onboarding/leads/$id/validate', 'Validation passed: required fields, duplicates and formats'))),
        step(c.flag('gateway'), 'Payment gateway', 'Mapped on the primary bank account', HqButton('Verify', small: true, onPressed: () => _call('/admin/hq/onboarding/leads/$id/verify-gateway', 'Gateway verified'))),
        step(
          c.flag('approved'),
          'Approval',
          approval == 'pending' ? 'Waiting on a Super admin' : approval == 'none' ? 'Needs the activation workflow' : 'Last request was $approval',
          approval == 'pending'
              ? HqButton('View', small: true, onPressed: () => hqGo(context, '/approvals'))
              : HqButton('Send', small: true, onPressed: () => _call('/admin/hq/onboarding/leads/$id/send-for-approval', 'Sent for approval. Track it in Approvals.')),
        ),
      ]),
      if (_write)
        HqButton('Go live', icon: allOk ? 'rocket' : 'lock', small: true, kind: allOk ? BtnKind.primary : BtnKind.normal, onPressed: () => _call('/admin/hq/onboarding/leads/$id/go-live', '${p.str('name')} is live.')),
    ]);
  }

  Widget _liveCard(Map<String, dynamic> p) {
    final days = DateTime.now().difference(toDate(p['since']) ?? DateTime.now()).inDays;
    return _card([
      Row(children: [
        Avatar(initials(p.str('name')), tone: Tone.green, square: true),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.str('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.row),
            Text('${p.str('city')} · ${p.str('owner', '')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HqText.small),
          ]),
        ),
      ]),
      Wrap(spacing: 6, children: [
        if (p.strOrNull('planName') != null) Tag(p.str('planName'), tone: Tone.blue),
        Tag('${p.integer('students')} students', tone: Tone.mute),
        Tag('Live · ${days <= 0 ? 'today' : '$days days ago'}', tone: Tone.green),
      ]),
    ]);
  }
}

class _Col {
  const _Col(this.title, this.count, this.children);
  final String title;
  final int count;
  final List<Widget> children;
}

class _Sub extends StatelessWidget {
  const _Sub(this.t, this.n, this.tone);
  final String t;
  final int n;
  final Tone tone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: tone.color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Text(t.toUpperCase(), style: HqText.th.copyWith(color: tone.color, letterSpacing: .4)),
          const Spacer(),
          Text('$n', style: HqText.small),
        ]),
      );
}

class _None extends StatelessWidget {
  const _None();
  @override
  Widget build(BuildContext context) => const EmptyNote('Nothing here yet', padding: 14);
}

/// Shown once, right after a demo starts: the owner's first login, which is not shown again.
class _Credentials extends StatelessWidget {
  const _Credentials({required this.username, required this.password});
  final String username, password;

  @override
  Widget build(BuildContext context) {
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: HqText.small), Text(v, style: HqText.row.copyWith(fontSize: 15, letterSpacing: .5))])),
            HqButton('Copy', small: true, onPressed: () {
              Clipboard.setData(ClipboardData(text: v));
              showToast(context, 'Copied');
            }),
          ]),
        );
    return ModalFrame(
      title: 'Demo started',
      sub: "Give the owner these details to sign in to the Owleo Nest app",
      actions: [HqButton('Done', kind: BtnKind.primary, onPressed: () => Navigator.of(context).pop())],
      children: [
        row('Username', username),
        row('Temporary password', password),
        Text('This password is shown once. The owner is asked to change it at first sign in.', style: HqText.sub),
        const SizedBox(height: 14),
      ],
    );
  }
}
