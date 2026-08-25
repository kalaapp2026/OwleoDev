import 'package:nest_fe/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/artist_application/data/artist_application_api.dart';

final artistApplicationApiProvider = Provider((ref) => ArtistApplicationApi(ref.watch(dioClientProvider)));
final pendingArtistApplicationsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(artistApplicationApiProvider).listPending());

/// Super Admin review queue (PRD 7.4 addendum) - approve flips the applicant straight to Artist
/// (they can post to the feed immediately); reject leaves them as a Guest (view-only).
class ArtistApplicationsScreen extends ConsumerWidget {
  const ArtistApplicationsScreen({super.key, this.embedded = false});

  /// True when rendered as a tab inside AppShell, which already supplies the Scaffold's AppBar -
  /// a second one here would stack two title bars. False when pushed as its own page.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applicationsAsync = ref.watch(pendingArtistApplicationsProvider);

    return Scaffold(
      appBar: embedded ? null : AppBar(title: Text(AppLocalizations.of(context).artistApplicationsTitle)),
      body: AsyncValueView<List<ArtistApplication>>(
        value: applicationsAsync,
        onRetry: () => ref.invalidate(pendingArtistApplicationsProvider),
        data: (context, applications) {
          if (applications.isEmpty) {
            return const EmptyState(icon: Icons.palette_outlined, message: 'No pending artist applications.');
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(pendingArtistApplicationsProvider);
              await ref.read(pendingArtistApplicationsProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: applications.length,
              itemBuilder: (context, i) => _ApplicationCard(application: applications[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ApplicationCard extends ConsumerStatefulWidget {
  const _ApplicationCard({required this.application});
  final ArtistApplication application;

  @override
  ConsumerState<_ApplicationCard> createState() => _ApplicationCardState();
}

class _ApplicationCardState extends ConsumerState<_ApplicationCard> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    try {
      final api = ref.read(artistApplicationApiProvider);
      if (approve) {
        await api.approve(widget.application.id);
      } else {
        await api.reject(widget.application.id);
      }
      if (mounted) {
        AppNotice.success(
          context,
          approve ? '${widget.application.fullName ?? 'Applicant'} approved as Artist.' : 'Application rejected.',
        );
        ref.invalidate(pendingArtistApplicationsProvider);
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final application = widget.application;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
              child: Text(
                (application.fullName?.isNotEmpty ?? false) ? application.fullName![0].toUpperCase() : '?',
                style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(application.fullName ?? 'Unknown', style: Theme.of(context).textTheme.titleSmall),
                  Text('@${application.username ?? ''}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (_busy)
              const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              IconButton(
                icon: const Icon(Icons.check_circle_outline),
                color: Colors.green,
                tooltip: AppLocalizations.of(context).actionApprove,
                onPressed: () => _decide(true),
              ),
              IconButton(
                icon: const Icon(Icons.cancel_outlined),
                color: colorScheme.error,
                tooltip: AppLocalizations.of(context).actionReject,
                onPressed: () => _decide(false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
