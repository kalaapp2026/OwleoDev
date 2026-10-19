import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/choice_chips.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_settings_api.dart';
import 'package:nest_fe/features/academy/presentation/academy_settings_kit.dart';

/// Requests an academy has raised with the Owleo team.
///
/// Two audiences, one screen: an Academy Admin sees their own academy's requests and how each was
/// answered; the Super Admin ([platform]) sees every academy's, filters to what is waiting, and
/// approves or declines each with a note.
class AcademyRequestsScreen extends ConsumerStatefulWidget {
  const AcademyRequestsScreen({super.key, this.platform = false});

  final bool platform;

  @override
  ConsumerState<AcademyRequestsScreen> createState() => _AcademyRequestsScreenState();
}

class _AcademyRequestsScreenState extends ConsumerState<AcademyRequestsScreen> {
  String _filter = 'PENDING';

  ProviderListenable<AsyncValue<List<AcademyRequest>>> get _provider =>
      widget.platform ? allAcademyRequestsProvider(_filter == 'ALL' ? null : _filter) : myAcademyRequestsProvider;

  void _refresh() {
    if (widget.platform) {
      ref.invalidate(allAcademyRequestsProvider);
    } else {
      ref.invalidate(myAcademyRequestsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_provider);
    return SettingsPage(
      title: widget.platform ? 'Academy requests' : 'My requests',
      onRefresh: () async => _refresh(),
      children: [
        if (widget.platform) ...[
          AppChoiceChips<String>(
            options: const ['PENDING', 'ALL'],
            labelOf: (v) => v == 'PENDING' ? 'Waiting' : 'All',
            isSelected: (v) => v == _filter,
            onTap: (v) => setState(() => _filter = v),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        AsyncValueView<List<AcademyRequest>>(
          value: async,
          onRetry: _refresh,
          data: (context, requests) {
            if (requests.isEmpty) {
              return EmptyState(
                icon: Icons.inbox_outlined,
                message: widget.platform ? 'Nothing waiting for an answer.' : 'You have not sent any requests yet.',
              );
            }
            return Column(
              children: [
                for (final r in requests)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: _RequestCard(request: r, platform: widget.platform, onChanged: _refresh),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request, required this.platform, required this.onChanged});

  final AcademyRequest request;
  final bool platform;
  final VoidCallback onChanged;

  Future<void> _resolve(BuildContext context, WidgetRef ref, {required bool approve}) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve request?' : 'Decline request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (approve && request.kind == AcademyRequestKind.planChange)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('This switches the academy to the requested plan for future invoices.'),
              ),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note for the academy (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(approve ? 'Approve' : 'Decline')),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(academySettingsApiProvider).resolveRequest(request.id, approve: approve, note: text.isEmpty ? null : text);
      onChanged();
      if (context.mounted) AppNotice.success(context, approve ? 'Request approved.' : 'Request declined.');
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final (statusColor, statusLabel) = switch (request.status) {
      'APPROVED' => (palette.paidManual, 'APPROVED'),
      'DECLINED' => (palette.notPaid, 'DECLINED'),
      _ => (palette.gold, 'WAITING'),
    };
    final lines = <String>[
      if ((request.subject ?? '').isNotEmpty) request.subject!,
      if ((request.targetEmail ?? '').isNotEmpty) 'New owner: ${request.targetEmail}',
      if ((request.targetPlan ?? '').isNotEmpty) 'Requested plan: ${request.targetPlan}',
      if ((request.reason ?? '').isNotEmpty) 'Reason: ${request.reason}',
    ];

    return SettingsCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(request.kind.label, style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.heavy, color: palette.text)),
              ),
              StatusBadge(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (platform && (request.academyName ?? '').isNotEmpty) request.academyName!,
              if ((request.requestedByName ?? '').isNotEmpty) 'by ${request.requestedByName}',
              shortDate(request.createdAt),
            ].where((s) => s.isNotEmpty).join(' · '),
            style: TextStyle(fontSize: AppType.sm, color: palette.textFaint),
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(line, style: TextStyle(fontSize: AppType.base, color: palette.textMuted)),
            ),
          if ((request.details ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(request.details!, style: TextStyle(fontSize: AppType.base, height: 1.5, color: palette.text)),
            ),
          if ((request.resolutionNote ?? '').isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: AppRadii.all(AppRadii.lg)),
              child: Text('Reply: ${request.resolutionNote}', style: TextStyle(fontSize: AppType.base, color: palette.textMuted)),
            ),
          if (platform && request.isPending) ...[
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: Pressable(
                    onTap: () => _resolve(context, ref, approve: false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.all(AppRadii.lg),
                        border: Border.all(color: palette.notPaid.withValues(alpha: 0.4)),
                      ),
                      child: Text('Decline', style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.notPaid)),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: AppPrimaryButton(label: 'Approve', onPressed: () => _resolve(context, ref, approve: true)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
