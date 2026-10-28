import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/admin_welcome_header.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/next_classes_card.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/revenue_dues_card.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/stats_row.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/student_home_sections.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/student_material_strip.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/todays_schedule_card.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/student_summary.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/student_welcome_header.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/upcoming_events_card.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';

/// PRD 3.1: the ERP home screen. A Student sees the original tile-grid body (their "courses"
/// figure is their own enrolment count, never the academy's whole catalog); an Academy Admin or
/// Trainer sees the richer real-data home built from 07-module-dashboard.jsx - see the "Dashboard
/// v1" plan for exactly which of that reference's cards are backed by real data today and which
/// were deliberately left out rather than faked (growth trend, course leaderboard, birthdays,
/// activity feed).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final membership = user.activeMembership;
    final isStudent = membership?.roleType == 'STUDENT';

    return isStudent
        ? const _StudentDashboardBody()
        : const _AdminTrainerDashboardBody();
  }
}

class _StudentDashboardBody extends ConsumerWidget {
  const _StudentDashboardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final membership = user.activeMembership;
    final membershipId = membership?.membershipId;
    final academyId = membership?.academyId;
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    return RefreshIndicator(
      onRefresh: () async {
        if (membershipId != null) {
          ref.invalidate(studentAttendanceProvider(membershipId));
        }
        ref.invalidate(scheduleFeedProvider((from: today, to: today, courseId: null)));
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          StudentWelcomeHeader(user: user, membership: membership),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, AppSpacing.xxl, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (membershipId != null && academyId != null) ...[
                  StudentQuickStats(
                    membershipId: membershipId,
                    academyId: academyId,
                    courseCount: membership?.courseIds.length ?? 0,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  StudentAttendanceSummary(membershipId: membershipId),
                  const SizedBox(height: AppSpacing.xxl),
                ],
                const TodaysScheduleCard(),
                if (academyId != null) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  StudentUpcomingEvents(academyId: academyId),
                ],
                const SizedBox(height: AppSpacing.xxl),
                const StudentMaterialStrip(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTrainerDashboardBody extends ConsumerWidget {
  const _AdminTrainerDashboardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final membership = user.activeMembership;
    final academyId = membership?.academyId;
    final isAdmin = user.isActiveAcademyAdmin;
    bool holdsAny(List<String> keys) => isAdmin || keys.any(user.hasFeature);
    // Each card appears only for someone holding a feature it belongs to - a trainer granted Fees
    // entry on one course shouldn't be shown people-search or a schedule they have no business with.
    final canSeeFees = holdsAny([FeatureKeys.feesEntry, FeatureKeys.feesDashboard]);
    final canSeeSchedule =
        holdsAny([FeatureKeys.attendance, FeatureKeys.reschedule, FeatureKeys.batchScheduling]);
    final canSearchPeople = holdsAny([
      FeatureKeys.studentRegistration,
      FeatureKeys.trainerRegistration,
      FeatureKeys.batchCreation,
    ]);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardFeedProvider);
        ref.invalidate(activeCoursesProvider);
        await ref.read(activeCoursesProvider.future);
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const AdminWelcomeHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, AppSpacing.xxl, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DashboardStatsRow(isAdmin: isAdmin),
                const SizedBox(height: AppSpacing.xl),
                if (canSearchPeople) ...[
                  const _GlobalSearchBar(),
                  const SizedBox(height: AppSpacing.xxl),
                ],
                if (canSeeSchedule) ...[
                  // Each batch's next class, with a bell to remind its students and trainers.
                  const NextClassesCard(),
                  const SizedBox(height: AppSpacing.xxl),
                  const TodaysScheduleCard(),
                ],
                if (canSeeFees) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  const RevenueDuesCard(),
                ],
                if (academyId != null) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  UpcomingEventsCard(academyId: academyId),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The prototype's "Search students or trainers..." pill under the stat tiles. Opens the people
/// search rather than being a field itself, so the dashboard never grabs the keyboard.
class _GlobalSearchBar extends StatelessWidget {
  const _GlobalSearchBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: () => context.push('/erp/students'),
      borderRadius: AppRadii.all(AppRadii.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: palette.textFaint),
            const SizedBox(width: AppSpacing.lg),
            Text('Search students or trainers…',
                style: TextStyle(fontSize: AppType.md, fontWeight: AppType.regular, color: palette.textFaint)),
          ],
        ),
      ),
    );
  }
}
