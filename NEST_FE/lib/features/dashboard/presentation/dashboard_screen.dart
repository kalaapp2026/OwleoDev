import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/admin_welcome_header.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/revenue_dues_card.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/stats_row.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/student_summary.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/student_welcome_header.dart';
import 'package:nest_fe/features/dashboard/presentation/widgets/todays_schedule_card.dart';
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

class _AdminTrainerDashboardBody extends ConsumerWidget {
  const _AdminTrainerDashboardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final membership = user.activeMembership;
    final academyId = membership?.academyId;
    final canSeeFees =
        user.isActiveAcademyAdmin || user.hasFeature(FeatureKeys.feesEntry);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(activeCoursesProvider.future),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const AdminWelcomeHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, AppSpacing.xxl, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DashboardStatsRow(isAdmin: user.isActiveAcademyAdmin),
                const SizedBox(height: AppSpacing.xxl),
                const TodaysScheduleCard(),
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
