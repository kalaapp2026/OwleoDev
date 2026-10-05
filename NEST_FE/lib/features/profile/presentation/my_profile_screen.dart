import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/profile/data/self_profile.dart';
import 'package:nest_fe/features/profile/data/self_profile_api.dart';
import 'package:nest_fe/features/profile/presentation/edit_my_profile_screen.dart';
import 'package:nest_fe/features/profile/presentation/profile_sections.dart';
import 'package:nest_fe/features/profile/presentation/profile_widgets.dart';
import 'package:nest_fe/features/profile/presentation/record_screens.dart';

/// The signed-in person's own profile: identity, the academies they belong to and what they are
/// enrolled in there, personal details, and their self-logged performance and achievements.
class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  String? _academyId;
  bool _uploading = false;

  Future<void> _changePhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      await ref.read(selfProfileApiProvider).uploadPhoto(await file.readAsBytes(), file.name);
      ref.invalidate(selfProfileProvider);
      await ref.read(sessionControllerProvider.notifier).refreshProfile();
      if (mounted) AppNotice.success(context, 'Photo updated.');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final profileAsync = ref.watch(selfProfileProvider);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          if (profileAsync.hasValue)
            TextButton.icon(
              onPressed: () => _push(EditMyProfileScreen(profile: profileAsync.requireValue)),
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text('Edit'),
            ),
        ],
      ),
      body: AsyncValueView(
        value: profileAsync,
        onRetry: () => ref.invalidate(selfProfileProvider),
        data: (context, profile) => _body(context, profile),
      ),
    );
  }

  Widget _body(BuildContext context, SelfProfile p) {
    final palette = context.palette;
    final academies = p.academies;
    // Keep the pick across rebuilds, but fall back if the academy list changed under it.
    final active = academies.isEmpty
        ? null
        : academies.firstWhere((a) => a.academyId == _academyId, orElse: () => academies.first);
    final choices = [for (final a in academies) (id: a.academyId, name: a.academyName)];

    final achievements = ref.watch(achievementsProvider).valueOrNull ?? const <Achievement>[];
    final allLogs = ref.watch(performanceLogsProvider).valueOrNull ?? const <PerformanceLog>[];
    // A log with no academy (written before joining one) still belongs to this person.
    final logs = [
      for (final l in allLogs)
        if (active == null || l.academyId == null || l.academyId == active.academyId) l
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(selfProfileProvider);
        ref.invalidate(achievementsProvider);
        ref.invalidate(performanceLogsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.x6l),
        children: [
          // Hero
          ProfileHero(
            profile: p,
            avatar: GestureDetector(
              onTap: _uploading ? null : _changePhoto,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PhotoAvatar(name: p.fullName, url: p.profileImageUrl, size: 84),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 27,
                      height: 27,
                      decoration: BoxDecoration(
                        color: palette.gold,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.surfaceRaised, width: 2),
                      ),
                      child: _uploading
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.photo_camera_outlined, size: 13, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Academies + Enrollment
          if (active != null) ...[
            ProfileSection(title: 'Academies', child: _academyPicker(choices, active)),
            const SizedBox(height: AppSpacing.xl),
            EnrollmentCard(academy: active),
            const SizedBox(height: AppSpacing.xl),
          ],

          // Personal details
          PersonalDetailsCard(profile: p, emptyHint: 'Nothing added yet. Tap Edit to fill these in.'),
          const SizedBox(height: AppSpacing.x3l),

          // Performance log
          ProfileSection(
            title: 'My Performance Log',
            onAdd: () => _push(PerformanceLogFormScreen(academies: choices, defaultAcademyId: active?.academyId)),
            onViewAll: () => _push(PerformanceLogScreen(academies: choices, defaultAcademyId: active?.academyId)),
            child: logs.isEmpty
                ? ProfileEmptyNote(
                    'No performance logs yet${active == null ? '' : ' at ${active.academyName}'}. Add one to track exams, recitals, or feedback.')
                : Column(
                    children: [
                      for (final l in logs.take(2))
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: PerformanceLogCard(
                            log: l,
                            academies: choices,
                            onTap: () => _push(
                                PerformanceLogFormScreen(existing: l, academies: choices, defaultAcademyId: active?.academyId)),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.x3l),

          // Achievements
          ProfileSection(
            title: 'Achievements',
            onAdd: () => _push(AchievementFormScreen(academies: choices, defaultAcademyId: active?.academyId)),
            onViewAll: () => _push(AchievementsScreen(academies: choices, defaultAcademyId: active?.academyId)),
            child: Column(
              children: [
                AchievementStats(achievements: achievements),
                const SizedBox(height: AppSpacing.md),
                if (achievements.isEmpty)
                  const ProfileEmptyNote('No achievements added yet.')
                else
                  for (final a in achievements.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: AchievementCard(
                        achievement: a,
                        academies: choices,
                        onTap: () => _push(
                            AchievementFormScreen(existing: a, academies: choices, defaultAcademyId: active?.academyId)),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _academyPicker(List<AcademyChoice> choices, AcademyEnrolment active) {
    if (choices.length < 2) return AcademyRow(name: active.academyName);
    return AttachedSelect<AcademyChoice>(
      label: 'Academy',
      showLabel: false,
      options: choices,
      value: choices.firstWhere((c) => c.id == active.academyId),
      labelOf: (c) => c.name,
      onSelected: (c) => setState(() => _academyId = c.id),
    );
  }
}
