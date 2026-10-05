import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/features/academy/presentation/academy_profile_shared.dart' show AcademyLogoMark, academyProfileProvider;
import 'package:nest_fe/features/dashboard/presentation/widgets/student_welcome_header.dart' show DashboardCoverBackdrop;

/// The Admin/Trainer dashboard's cover hero: same treatment as [StudentWelcomeHeader], but
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
    final logoColor = profileAsync.maybeWhen(data: (p) => p.logoColor, orElse: () => null);
    final coverUrl = profileAsync.maybeWhen(data: (p) => p.coverImageUrl, orElse: () => null);
    final coverStyle = profileAsync.maybeWhen(data: (p) => p.coverStyle, orElse: () => null);
    const coverHeight = 150.0;
    const logoSize = 64.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The academy's own cover (photo, else its chosen preset), running up behind the
        // transparent app bar. The logo tile overlaps its bottom edge.
        SizedBox(
          height: coverHeight + logoSize / 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              DashboardCoverBackdrop(imageUrl: coverUrl, styleKey: coverStyle, height: coverHeight),
              Positioned(
                left: 20,
                top: coverHeight - logoSize / 2,
                child: AcademyLogoMark(name: name, imageUrl: logoUrl, colorKey: logoColor, size: logoSize, borderColor: palette.bg),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, AppSpacing.xxl),
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
