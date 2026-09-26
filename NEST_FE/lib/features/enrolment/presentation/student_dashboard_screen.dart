import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/attendance/presentation/student_attendance_screen.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/fees/presentation/student_profile_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// The read-only student profile: an identity header everyone with access to this screen sees,
/// plus a Fees and an Attendance section shown only to whoever holds the matching feature -
/// mirrors the reference's own canSeeFees/canSeeAttendance gating. Reuses the fully-built Fees
/// student profile and the Attendance history screen for their sections rather than
/// re-implementing either.
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
    final cardAsync = ref.watch(studentCardProvider(membershipId));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(title: const Text('Student Profile')),
      body: AsyncValueView<StudentCard>(
        value: cardAsync,
        onRetry: () => ref.invalidate(studentCardProvider(membershipId)),
        data: (context, card) => ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            _IdentityHeader(card: card),
            const SizedBox(height: AppSpacing.x4l),
            if (card.courses.isNotEmpty) ...[
              _SectionLabel('Enrolled in'),
              const SizedBox(height: AppSpacing.md),
              ...card.courses.map((c) => _CourseTile(course: c)),
              const SizedBox(height: AppSpacing.x4l),
            ],
            _SectionLabel('Open'),
            const SizedBox(height: AppSpacing.md),
            if (canSeeAttendance)
              _ActionTile(
                icon: Icons.fact_check_outlined,
                color: palette.primary,
                title: 'Attendance',
                subtitle: 'Marked sessions by month',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentAttendanceScreen(membershipId: membershipId, studentName: card.fullName),
                  ),
                ),
              ),
            if (canSeeFees)
              _ActionTile(
                icon: Icons.account_balance_wallet_outlined,
                color: palette.gold,
                title: 'Fees',
                subtitle: 'Balance, statement and payments',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentProfileScreen(membershipId: membershipId, period: _currentPeriod()),
                  ),
                ),
              ),
            if (!canSeeFees && !canSeeAttendance)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Text(
                  'You do not hold a feature that opens a section here yet.',
                  style: TextStyle(color: palette.textMuted, fontSize: AppType.md),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.card});
  final StudentCard card;

  Future<void> _launch(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open that.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x4l),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Column(
        children: [
          PersonAvatar(name: card.fullName, seed: card.membershipId, size: 72),
          const SizedBox(height: AppSpacing.lg),
          Text(card.fullName,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.bold, color: palette.text)),
          if (card.joiningDate != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text('With us since ${card.joiningDate!.split('-').first}',
                style: TextStyle(fontSize: AppType.sm, color: palette.textMuted)),
          ],
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              if (card.phone != null)
                _ContactChip(icon: Icons.call_outlined, label: card.phone!,
                    onTap: () => _launch(context, Uri(scheme: 'tel', path: card.phone))),
              if (card.email != null)
                _ContactChip(icon: Icons.mail_outline, label: card.email!,
                    onTap: () => _launch(context, Uri(scheme: 'mailto', path: card.email))),
            ],
          ),
          if (card.guardianName != null || card.address != null) ...[
            const SizedBox(height: AppSpacing.xl),
            Divider(color: palette.borderSoft, height: 1),
            const SizedBox(height: AppSpacing.xl),
          ],
          if (card.guardianName != null)
            _InfoRow(icon: Icons.family_restroom_outlined, label: 'Guardian', value: card.guardianName!),
          if (card.address != null)
            _InfoRow(icon: Icons.place_outlined, label: 'Address',
                value: [card.address, card.city, card.state].whereType<String>().join(', ')),
        ],
      ),
    );
  }
}

class _ContactChip extends StatelessWidget {
  const _ContactChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: palette.primarySoft,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: palette.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: TextStyle(fontSize: AppType.sm, color: palette.primary, fontWeight: AppType.medium)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: palette.textFaint),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
                Text(value, style: TextStyle(fontSize: AppType.md, color: palette.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: TextStyle(
          fontSize: AppType.xs,
          fontWeight: AppType.bold,
          letterSpacing: 0.6,
          color: context.palette.textFaint,
        ));
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course});
  final StudentCardCourse course;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_stories_outlined, size: 18, color: palette.primary),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.courseName, style: TextStyle(fontSize: AppType.md, fontWeight: AppType.medium, color: palette.text)),
                if (course.batchName != null)
                  Text(course.batchName!, style: TextStyle(fontSize: AppType.xs, color: palette.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: palette.borderSoft),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.13), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.bold, color: palette.text)),
                  Text(subtitle, style: TextStyle(fontSize: AppType.sm, color: palette.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: palette.textFaint),
          ],
        ),
      ),
    );
  }
}
