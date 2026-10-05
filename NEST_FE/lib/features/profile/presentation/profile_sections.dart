import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/features/enrolment/data/person_details.dart' show ageFrom;
import 'package:nest_fe/features/profile/data/self_profile.dart';
import 'package:nest_fe/features/profile/presentation/profile_widgets.dart';

/// Shared by the student's own profile and the staff view of a student, so the two cannot drift.

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.color, required this.soft, required this.title, this.subtitle});
  final IconData icon;
  final Color color;
  final Color soft;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: soft, borderRadius: AppRadii.all(AppRadii.sm)),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: AppType.lg, fontWeight: AppType.heavy, color: palette.text)),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The top card: avatar, name, @username, email, account age, then Phone and Email rows.
/// [avatar] is supplied so the student's own screen can make it a photo-change button.
class ProfileHero extends StatelessWidget {
  const ProfileHero({super.key, required this.profile, required this.avatar, this.onPhoneTap, this.onEmailTap});
  final SelfProfile profile;
  final Widget avatar;
  final VoidCallback? onPhoneTap;
  final VoidCallback? onEmailTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final p = profile;
    final hasPhone = p.phone != null && p.phone!.isNotEmpty;
    return ProfileCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.x5l, AppSpacing.xl, AppSpacing.x3l),
      child: Column(
        children: [
          avatar,
          const SizedBox(height: AppSpacing.xl),
          Text(p.fullName,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: AppType.heavy, color: palette.text)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_outlined, size: 12, color: palette.primary),
              const SizedBox(width: 5),
              Text('@${p.username}',
                  style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.bold, color: palette.primary)),
            ],
          ),
          if (p.email != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(p.email!, style: TextStyle(fontSize: AppType.md, color: palette.textMuted)),
            ),
          if (p.onPlatformSince != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('Owleo Account · On Owleo since ${longDate(p.onPlatformSince!)}',
                  style: TextStyle(fontSize: 10, color: palette.textFaint)),
            ),
          if (hasPhone) ...[
            const SizedBox(height: AppSpacing.xxl),
            Divider(height: 1, color: palette.borderSoft),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: InfoLine(
                  label: 'Phone',
                  icon: Icons.phone_outlined,
                  onTap: onPhoneTap,
                  value: (p.altPhone ?? '').isEmpty ? p.phone : '${p.phone} · ${p.altPhone} (alt)',
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: InfoLine(label: 'Email', icon: Icons.mail_outline, value: p.email, onTap: onEmailTap),
            ),
          ],
        ],
      ),
    );
  }
}

/// The single, non-selectable academy row shown under "Academies".
class AcademyRow extends StatelessWidget {
  const AcademyRow({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ProfileCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: palette.goldSoft, borderRadius: AppRadii.all(AppRadii.md)),
            child: Icon(Icons.apartment_outlined, size: 14, color: palette.gold),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text)),
          ),
        ],
      ),
    );
  }
}

/// A read-only "View all" list: title with the person's name beneath, then the cards.
class RecordsListScreen extends StatelessWidget {
  const RecordsListScreen({super.key, required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: AppType.title, fontWeight: AppType.bold)),
            Text(subtitle, style: TextStyle(fontSize: AppType.smd, color: palette.textMuted)),
          ],
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

class EnrollmentCard extends StatelessWidget {
  const EnrollmentCard({super.key, required this.academy});
  final AcademyEnrolment academy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
              icon: Icons.school_outlined,
              color: palette.primary,
              soft: palette.primarySoft,
              title: 'Enrollment',
              subtitle: academy.academyName),
          if (academy.courses.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: Text('Not enrolled in any course here yet.',
                  style: TextStyle(fontSize: AppType.smd, color: palette.textFaint)),
            ),
          for (final c in academy.courses)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.md),
              padding: const EdgeInsets.only(top: AppSpacing.md),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.borderSoft))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5, right: AppSpacing.md),
                    decoration: BoxDecoration(color: palette.gold, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.courseName,
                            style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text)),
                        if (c.trainers.isNotEmpty)
                          Text('Trainer: ${c.trainers.join(', ')}',
                              style: TextStyle(fontSize: AppType.xs, color: palette.textFaint)),
                      ],
                    ),
                  ),
                  if (academy.joiningDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Joined ${dmyDate(academy.joiningDate!)}',
                          style: TextStyle(fontSize: AppType.tiny, color: palette.textFaint)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class PersonalDetailsCard extends StatelessWidget {
  const PersonalDetailsCard({super.key, required this.profile, this.emptyHint = 'Nothing added yet.'});
  final SelfProfile profile;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final p = profile;
    final age = ageFrom(p.dob);
    final empty = p.dob == null &&
        (p.gender ?? '').isEmpty &&
        (p.bloodGroup ?? '').isEmpty &&
        (p.guardianName ?? '').isEmpty &&
        p.formattedAddress.isEmpty;
    return ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
              icon: Icons.person_outline, color: palette.violet, soft: palette.violetSoft, title: 'Personal Details'),
          const SizedBox(height: AppSpacing.md),
          InfoLine(
            label: 'Date of birth',
            icon: Icons.cake_outlined,
            value: p.dob == null ? null : '${longDate(p.dob!)}${age == null ? '' : ' · $age yrs'}',
          ),
          InfoLine(label: 'Gender', value: p.gender),
          InfoLine(label: 'Blood group', icon: Icons.water_drop_outlined, value: p.bloodGroup),
          InfoLine(label: 'Guardian', value: p.guardianName),
          InfoLine(label: 'Address', icon: Icons.location_on_outlined, value: p.formattedAddress),
          if (empty) Text(emptyHint, style: TextStyle(fontSize: AppType.smd, color: palette.textFaint)),
        ],
      ),
    );
  }
}

class StatPill extends StatelessWidget {
  const StatPill({super.key, required this.icon, required this.color, required this.soft, required this.value, required this.label});
  final IconData icon;
  final Color color;
  final Color soft;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: soft,
          borderRadius: AppRadii.all(AppRadii.lg),
          border: Border.all(color: color.withValues(alpha: 0.27)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value', style: TextStyle(fontSize: 15, fontWeight: AppType.heavy, color: color, height: 1)),
                const SizedBox(height: 2),
                Text(label.toUpperCase(),
                    style: TextStyle(fontSize: 9, fontWeight: AppType.bold, color: color, letterSpacing: 0.3)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Total / Certificates" pair above the achievement list.
class AchievementStats extends StatelessWidget {
  const AchievementStats({super.key, required this.achievements});
  final List<Achievement> achievements;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        StatPill(icon: Icons.emoji_events_outlined, color: palette.gold, soft: palette.goldSoft, value: achievements.length, label: 'Total'),
        const SizedBox(width: AppSpacing.md),
        StatPill(
          icon: Icons.school_outlined,
          color: palette.primary,
          soft: palette.primarySoft,
          value: achievements.where((a) => a.type == 'CERTIFICATE').length,
          label: 'Certificates',
        ),
      ],
    );
  }
}
