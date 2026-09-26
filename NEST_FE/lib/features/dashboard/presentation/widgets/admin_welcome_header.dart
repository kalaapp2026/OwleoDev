import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/features/academy/presentation/academy_info_screen.dart' show academyProfileProvider;
import 'package:nest_fe/features/dashboard/presentation/widgets/student_welcome_header.dart'
    show kDashboardHeroGradient;

/// The Admin/Trainer dashboard's gradient hero: same treatment as [StudentWelcomeHeader], but
/// showing the academy's own identity (logo, name, tagline) instead of a personal greeting -
/// matches the reference's admin dashboard. Reuses [academyProfileProvider] (already fetched by
/// the Academy Profile screen) rather than adding a second endpoint for the same data; while it's
/// loading or on error this falls back to the membership's own academyName so the header never
/// shows blank.
class AdminWelcomeHeader extends ConsumerWidget {
  const AdminWelcomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final membership = ref.watch(sessionControllerProvider).user?.activeMembership;
    final profileAsync = ref.watch(academyProfileProvider);
    final name = profileAsync.maybeWhen(
      data: (p) => p.name,
      orElse: () => membership?.academyName ?? 'Academy',
    );
    final tagline = profileAsync.maybeWhen(data: (p) => p.tagline, orElse: () => null);
    final logoUrl = profileAsync.maybeWhen(data: (p) => p.logoUrl, orElse: () => null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: kDashboardHeroGradient),
          child: SizedBox(height: 92),
        ),
        // Lifts the tile up to overlap the gradient hero above - Container.margin can't express
        // that (it asserts every inset is non-negative), so the overlap has to come from a
        // transform instead of a negative margin.
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Transform.translate(
            offset: const Offset(0, -28),
            child: _AcademyLogoTile(name: name, logoUrl: logoUrl, size: 64),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.x3l,
                  fontWeight: AppType.heavy,
                  letterSpacing: AppType.titleTracking,
                  color: palette.text,
                ),
              ),
              if (tagline != null && tagline.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  tagline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.semi, color: palette.textMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AcademyLogoTile extends StatelessWidget {
  const _AcademyLogoTile({required this.name, required this.logoUrl, required this.size});

  final String name;
  final String? logoUrl;
  final double size;

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final first = words.isNotEmpty ? words[0][0] : '';
    final second = words.length > 1 ? words[1][0] : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resolvedUrl = ApiConfig.resolveMediaUrl(logoUrl);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.gold,
        borderRadius: AppRadii.all(AppRadii.xl),
        border: Border.all(color: palette.surfaceRaised, width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: resolvedUrl != null
          ? Image.network(resolvedUrl, fit: BoxFit.cover)
          : Center(
              child: Text(
                _initials,
                style: TextStyle(fontSize: size * 0.36, fontWeight: AppType.heavy, color: Colors.black),
              ),
            ),
    );
  }
}
