import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/sections.dart';
import '../academies/academy_form.dart';
import 'onboarding_screen.dart';

/// Opens the full-screen Add pre-lead form. On success the pre-lead appears in the pipeline.
Future<void> showAddPreLead(BuildContext context, WidgetRef ref) async {
  final done = await showHqFullPage<bool>(context, builder: (_) => const AddPreLeadPage());
  if (done == true) {
    ref.invalidate(onboardingProvider);
    if (context.mounted) showToast(context, 'Added to Onboarding as a pre-lead');
  }
}

/// A pre-lead is an academy HQ has heard of and wants to follow up: only the academy's own details.
/// There is no owner, plan or bank account here - those are collected when it becomes a lead.
class AddPreLeadPage extends ConsumerStatefulWidget {
  const AddPreLeadPage({super.key});

  @override
  ConsumerState<AddPreLeadPage> createState() => _AddPreLeadPageState();
}

class _AddPreLeadPageState extends ConsumerState<AddPreLeadPage> {
  final AcademyFormData _data = AcademyFormData();
  final Set<String> _open = {'details', 'address'};
  bool _busy = false;

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final issues = _data.issues(preLead: true);
    if (issues.isNotEmpty) {
      setState(() => _open.add(issues.first.$1));
      showToast(context, issues.first.$2);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(dioClientProvider).postMap('/admin/hq/onboarding/preleads', body: _data.toJson());
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
    void toggle(String k) => setState(() => _open.contains(k) ? _open.remove(k) : _open.add(k));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListenableBuilder(
          listenable: _data,
          builder: (context, _) {
            final issues = _data.issues(preLead: true);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FormTopBar(
                  title: 'Add pre-lead',
                  subtitle: 'Academy details only. Owner, plan and banks come at lead.',
                  onBack: () => Navigator.of(context).pop(),
                ),
                AcademyFormSections(data: _data, open: _open, onToggle: toggle, preLead: true),
                HqButton('Save pre-lead', icon: 'check', kind: BtnKind.primary, expand: true, busy: _busy, onPressed: issues.isEmpty ? _submit : null),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: issues.isEmpty ? null : () => setState(() => _open.add(issues.first.$1)),
                      child: Text(issues.isEmpty ? 'Ready to add to the pipeline.' : issues.first.$2, textAlign: TextAlign.center, style: HqText.muted),
                    ),
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}
