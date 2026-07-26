import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/artist_application/presentation/artist_applications_screen.dart';

/// "Are you an artist?" (PRD 7.4 addendum) - shown right after Guest signup, and reachable again
/// later from Profile for anyone who skipped it or was rejected and wants to reapply. Yes sends
/// the application to Super Admin for review; the person stays a Guest (view-only) until decided.
class BecomeArtistScreen extends ConsumerStatefulWidget {
  const BecomeArtistScreen({super.key});

  @override
  ConsumerState<BecomeArtistScreen> createState() => _BecomeArtistScreenState();
}

class _BecomeArtistScreenState extends ConsumerState<BecomeArtistScreen> {
  bool _isSubmitting = false;

  Future<void> _apply() async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(artistApplicationApiProvider).apply();
      if (mounted) {
        AppNotice.success(context, "Application submitted - you'll hear back once Super Admin reviews it.");
        context.go('/home');
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.palette_outlined, size: 56, color: colorScheme.primary),
                  const SizedBox(height: 20),
                  Text('Are you an artist?', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(
                    "Artists can post to the feed. Apply now and Super Admin will review it - you'll stay a Guest (view-only) until then.",
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _apply,
                    child: _isSubmitting
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text("Yes, I'm an artist"),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => context.go('/home'),
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
