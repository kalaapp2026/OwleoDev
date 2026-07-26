import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_onboarding_api.dart';
import 'package:nest_fe/features/academy/presentation/academy_onboarding_screen.dart';

/// Super Admin tenant management (PRD 2.4): list every academy, onboard a new one, and suspend or
/// reactivate an existing one. Suspending an academy locks out its whole tenant - students,
/// trainers, and its Academy Admin - until Super Admin reactivates it.
class AcademyManagementScreen extends ConsumerWidget {
  const AcademyManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final academiesAsync = ref.watch(allAcademiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Academies')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('New academy'),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AcademyOnboardingScreen()),
          );
          ref.invalidate(allAcademiesProvider);
        },
      ),
      body: AsyncValueView<List<AcademyBrief>>(
        value: academiesAsync,
        onRetry: () => ref.invalidate(allAcademiesProvider),
        data: (context, academies) {
          if (academies.isEmpty) {
            return const EmptyState(icon: Icons.account_balance_outlined, message: 'No academies onboarded yet.');
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(allAcademiesProvider);
              await ref.read(allAcademiesProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: academies.length,
              itemBuilder: (context, i) => _AcademyCard(academy: academies[i]),
            ),
          );
        },
      ),
    );
  }
}

class _AcademyCard extends ConsumerStatefulWidget {
  const _AcademyCard({required this.academy});
  final AcademyBrief academy;

  @override
  ConsumerState<_AcademyCard> createState() => _AcademyCardState();
}

class _AcademyCardState extends ConsumerState<_AcademyCard> {
  bool _busy = false;

  Future<void> _toggle(bool active) async {
    final academy = widget.academy;
    // Suspending locks out the whole tenant - make the Super Admin confirm that.
    if (!active) {
      final ok = await AppNotice.confirm(
        context,
        title: 'Suspend ${academy.name}?',
        message: 'Everyone in this academy - students, trainers, and its admin - will lose access until you reactivate it.',
        confirmLabel: 'Suspend',
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(academyOnboardingApiProvider).setStatus(academy.id, active ? 'ACTIVE' : 'SUSPENDED');
      if (mounted) {
        AppNotice.success(context, active ? '${academy.name} reactivated.' : '${academy.name} suspended.');
        ref.invalidate(allAcademiesProvider);
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final academy = widget.academy;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: Icon(
          Icons.account_balance_outlined,
          color: academy.isSuspended ? colorScheme.error : colorScheme.primary,
        ),
        title: Text(academy.name),
        subtitle: Text(
          academy.isSuspended ? 'Suspended' : 'Active',
          style: TextStyle(color: academy.isSuspended ? colorScheme.error : null),
        ),
        trailing: _busy
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Switch(
                value: !academy.isSuspended,
                onChanged: (v) => _toggle(v),
              ),
      ),
    );
  }
}
