import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/attendance/presentation/student_attendance_screen.dart';
import 'package:nest_fe/features/fees/presentation/student_profile_screen.dart';
import 'package:nest_fe/features/profile/data/self_profile.dart';
import 'package:nest_fe/features/profile/data/self_profile_api.dart';
import 'package:nest_fe/features/profile/presentation/performance_cards.dart';
import 'package:nest_fe/features/profile/presentation/profile_sections.dart';
import 'package:nest_fe/features/profile/presentation/profile_widgets.dart';
import 'package:nest_fe/features/profile/presentation/record_screens.dart';
import 'package:url_launcher/url_launcher.dart';

/// The staff view of a student (More > Students > a student): identity, enrollment and personal
/// details, the student's self-logged performance and achievements (read-only here), plus Fees
/// and Attendance shown only to whoever holds the matching feature. Fees and Attendance reuse the
/// fully-built screens rather than re-implementing either.
class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key, required this.membershipId});

  final String membershipId;

  static String _currentPeriod() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final user = ref.watch(sessionControllerProvider).user;
    final canSeeFees = user != null && (user.isActiveAcademyAdmin || user.hasFeature(FeatureKeys.feesEntry));
    final canSeeAttendance = user != null && (user.isActiveAcademyAdmin || user.hasFeature(FeatureKeys.attendance));
    final async = ref.watch(studentProfileProvider(membershipId));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Student Profile', style: TextStyle(fontSize: AppType.title, fontWeight: AppType.bold)),
            if (async.hasValue)
              Text(async.requireValue.profile.fullName,
                  style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
          ],
        ),
      ),
      body: AsyncValueView<StudentProfile>(
        value: async,
        onRetry: () => ref.invalidate(studentProfileProvider(membershipId)),
        data: (context, sp) {
          final p = sp.profile;
          final academy = p.academies.isEmpty ? null : p.academies.first;
          // Staff see this academy only, so the cards have no academy badge to show.
          const academies = <AcademyChoice>[];
          void open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
          Future<void> launch(Uri uri) async {
            if (!await launchUrl(uri) && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open that.')));
            }
          }

          final logCards = [for (final l in sp.performanceLogs) PerformanceLogCard(log: l, academies: academies)];
          final achievementCards = [for (final a in sp.achievements) AchievementCard(achievement: a, academies: academies)];
          Widget stacked(List<Widget> cards) => Column(
                children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.lg), child: c)],
              );

          // Same order and shape as the student's own profile; staff-only Fees/Attendance go last.
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(studentProfileProvider(membershipId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.x6l),
              children: [
                ProfileHero(
                  profile: p,
                  avatar: PhotoAvatar(name: p.fullName, url: p.profileImageUrl, size: 84),
                  onPhoneTap: p.phone == null ? null : () => launch(Uri(scheme: 'tel', path: p.phone)),
                  onEmailTap: p.email == null ? null : () => launch(Uri(scheme: 'mailto', path: p.email)),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (academy != null) ...[
                  ProfileSection(title: 'Academies', child: AcademyRow(name: academy.academyName)),
                  const SizedBox(height: AppSpacing.xl),
                  EnrollmentCard(academy: academy),
                  const SizedBox(height: AppSpacing.xl),
                ],
                PersonalDetailsCard(profile: p),
                const SizedBox(height: AppSpacing.x3l),
                ProfileSection(
                  title: 'Performance Log',
                  onViewAll: logCards.length > 2
                      ? () => open(RecordsListScreen(title: 'Performance Log', subtitle: p.fullName, children: logCards))
                      : null,
                  child: logCards.isEmpty
                      ? ProfileEmptyNote(
                          'No performance logs yet${academy == null ? '' : ' at ${academy.academyName}'}.')
                      : stacked(logCards.take(2).toList()),
                ),
                const SizedBox(height: AppSpacing.x3l),
                ProfileSection(
                  title: 'Achievements',
                  onViewAll: achievementCards.length > 3
                      ? () => open(RecordsListScreen(title: 'Achievements', subtitle: p.fullName, children: achievementCards))
                      : null,
                  child: Column(children: [
                    AchievementStats(achievements: sp.achievements),
                    const SizedBox(height: AppSpacing.md),
                    if (achievementCards.isEmpty)
                      const ProfileEmptyNote('No achievements added yet.')
                    else
                      stacked(achievementCards.take(3).toList()),
                  ]),
                ),
                // Fees / Attendance summaries - shown only to whoever holds the matching feature.
                if (canSeeAttendance || canSeeFees) ...[
                  const SizedBox(height: AppSpacing.x3l),
                  PerformanceLabel(academy?.academyName),
                ],
                if (canSeeFees) ...[
                  FeesSummaryCard(
                    membershipId: membershipId,
                    onOpenFull: () => open(StudentProfileScreen(membershipId: membershipId, period: _currentPeriod())),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
                if (canSeeAttendance)
                  AttendanceSummaryCard(
                    membershipId: membershipId,
                    onOpenFull: () => open(StudentAttendanceScreen(membershipId: membershipId, studentName: p.fullName)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
