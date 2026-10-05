import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';
import 'package:nest_fe/features/academy/presentation/academy_profile_edit_screen.dart';
import 'package:nest_fe/features/academy/presentation/academy_profile_shared.dart';
import 'package:nest_fe/features/academy/presentation/trainer_card_screen.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/dashboard/data/dashboard_api.dart';

export 'package:nest_fe/features/academy/presentation/academy_profile_shared.dart' show academyProfileApiProvider, academyProfileProvider;

/// Academy Profile (More > Academy Profile) - the academy's public page. Everyone in the academy
/// can read it; only an Academy Admin gets the edit affordances (ABOUT_US_EDIT is non-delegable).
///
/// Two screens, as in the prototype: this view and [AcademyProfileEditScreen]. Edits live in a
/// local [ProfileDraft] until Publish, and this view always renders the draft - so view and
/// preview are the same screen. Highlights and branches keep their own immediate add/remove.
class AcademyInfoScreen extends ConsumerStatefulWidget {
  const AcademyInfoScreen({super.key});

  @override
  ConsumerState<AcademyInfoScreen> createState() => _AcademyInfoScreenState();
}

class _AcademyInfoScreenState extends ConsumerState<AcademyInfoScreen> {
  ProfileDraft? _draft;
  bool _isPublishing = false;

  ProfileDraft _draftFor(AcademyProfile profile) => _draft ??= ProfileDraft.from(profile);

  bool get _canEdit {
    final user = ref.read(sessionControllerProvider).user;
    return user != null && (user.isSuperAdmin || user.isActiveAcademyAdmin);
  }

  Future<void> _openEdit(AcademyProfile profile) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AcademyProfileEditScreen(
        published: profile,
        draft: _draftFor(profile),
        onChanged: () => setState(() {}),
        onDiscard: _resetDraft,
      ),
    ));
    if (mounted) setState(() {});
  }

  void _resetDraft() {
    setState(() => _draft = null);
    showAppToast(context, 'Draft changes discarded');
  }

  Future<void> _confirmDiscard() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Discard draft changes?',
      message: "Your edits will be reverted back to the last published version of the profile. This can't be undone.",
      confirmLabel: 'Discard',
    );
    if (confirmed) _resetDraft();
  }

  Future<void> _publish(AcademyProfile published) async {
    final draft = _draftFor(published);
    final problem = draft.validationError();
    if (problem != null) {
      AppNotice.error(context, problem);
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Publish these changes?',
      message: 'Your academy profile will update immediately for anyone viewing it — students, parents and visitors.',
      confirmLabel: 'Publish',
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isPublishing = true);
    try {
      final api = ref.read(academyProfileApiProvider);
      if (draft.newLogoBytes != null) {
        await api.uploadLogo(draft.newLogoBytes!, draft.newLogoName ?? 'logo.jpg');
      }
      if (draft.newCoverBytes != null) {
        await api.uploadCoverImage(draft.newCoverBytes!, draft.newCoverName ?? 'cover.jpg');
      }
      await api.publishProfile(draft.toBody(published: published));
      // The academy name also lives on the session's membership (shell header, switcher).
      if (draft.name.trim() != published.name) {
        await ref.read(sessionControllerProvider.notifier).refreshProfile();
      }
      _draft = null;
      ref.invalidate(academyProfileProvider);
      if (mounted) showAppToast(context, 'Academy profile published');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    ref.watch(sessionControllerProvider);
    final canEdit = _canEdit;
    final profileAsync = ref.watch(academyProfileProvider);
    final published = profileAsync.valueOrNull;
    final isDirty = canEdit && published != null && _draft != null && _draft!.isDirtyAgainst(published);

    return PopScope(
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showAppConfirmDialog(
          context: context,
          title: 'Leave without publishing?',
          message: 'Your draft changes will be lost. Publish them first if students should see them.',
          confirmLabel: 'Leave',
        );
        if (leave && context.mounted) {
          setState(() => _draft = null);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: palette.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppTopBar(
                title: 'Academy Profile',
                subtitle: !canEdit
                    ? null
                    : isDirty
                        ? 'Showing your unpublished draft'
                        : 'This is your live public page',
                actions: [
                  if (canEdit && published != null)
                    AppIconButton(icon: Icons.edit_outlined, onTap: () => _openEdit(published)),
                ],
              ),
              Expanded(
                child: AsyncValueView<AcademyProfile>(
                  value: profileAsync,
                  onRetry: () => ref.invalidate(academyProfileProvider),
                  data: (context, profile) => _ProfileView(
                    profile: profile,
                    draft: _draftFor(profile),
                    canEdit: canEdit,
                    isDirty: isDirty,
                  ),
                ),
              ),
              if (canEdit && published != null)
                _BottomActionBar(
                  isDirty: isDirty,
                  isPublishing: _isPublishing,
                  onEdit: () => _openEdit(published),
                  onPublish: () => _publish(published),
                  onDiscard: _confirmDiscard,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, this.color, this.trailing});
  final IconData icon;
  final String title;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(icon, size: 14, color: color ?? palette.primary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(title, style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text))),
        ?trailing,
      ],
    );
  }
}

/// Students/Trainers/Courses, read from the same sources as the Dashboard's stats row so the two
/// screens can never disagree. Not editable - the edit screen says so.
class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(activeCoursesProvider);
    final statsAsync = ref.watch(dashboardStatsProvider);
    final courseCount = coursesAsync.maybeWhen(data: (c) => '${c.length}', orElse: () => '—');
    final studentCount = statsAsync.maybeWhen(data: (s) => '${s.totalStudents}', orElse: () => '—');
    final trainerCount = statsAsync.maybeWhen(data: (s) => '${s.totalTrainers}', orElse: () => '—');
    final palette = context.palette;

    return Row(
      children: [
        Expanded(child: _StatTile(icon: Icons.groups_outlined, value: studentCount, label: 'Active students', color: palette.primary)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _StatTile(icon: Icons.school_outlined, value: trainerCount, label: 'Trainers', color: palette.gold)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _StatTile(icon: Icons.menu_book_outlined, value: courseCount, label: 'Courses', color: palette.violet)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label, required this.color});
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border.all(color: palette.borderSoft),
        borderRadius: AppRadii.all(AppRadii.xl),
      ),
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: AppRadii.all(9)),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: TextStyle(fontSize: AppType.title, fontWeight: AppType.heavy, color: palette.text, letterSpacing: -0.3)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppType.micro, fontWeight: AppType.bold, color: palette.textMuted, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

/// Read-only presentation of the draft, styled the way a visitor sees the page. No inline edit
/// affordances for profile fields - those all live on the edit screen.
class _ProfileView extends StatelessWidget {
  const _ProfileView({required this.profile, required this.draft, required this.canEdit, required this.isDirty});

  final AcademyProfile profile;
  final ProfileDraft draft;
  final bool canEdit;
  final bool isDirty;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final linkKeys = [...socialLinkKeys, 'maps'].where(draft.linkVisible).toList();
    const coverHeight = 148.0;
    const logoSize = 68.0;

    return Column(
      children: [
        if (isDirty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: AppSpacing.sm),
            decoration: BoxDecoration(color: palette.goldSoft, border: Border(bottom: BorderSide(color: palette.border))),
            child: Row(
              children: [
                Icon(Icons.visibility_off_outlined, size: 13, color: palette.gold),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Only you can see this — students still see the published version',
                    style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.gold),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AcademyCover(imageUrl: draft.coverUrl, styleKey: draft.coverStyle, pendingBytes: draft.newCoverBytes, height: coverHeight),
                  Positioned(
                    left: AppSpacing.page,
                    top: coverHeight - logoSize / 2,
                    child: AcademyLogoMark(
                      name: draft.name,
                      imageUrl: draft.logoUrl,
                      colorKey: draft.logoColor,
                      pendingBytes: draft.newLogoBytes,
                      size: logoSize,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 42, AppSpacing.page, AppSpacing.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(draft.name,
                                  style: TextStyle(fontSize: AppType.display + 1, fontWeight: AppType.heavy, color: palette.text, letterSpacing: -0.3)),
                              if (draft.tagline.trim().isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(draft.tagline, style: TextStyle(fontSize: AppType.md, color: palette.textMuted)),
                              ],
                            ],
                          ),
                        ),
                        if (canEdit) ...[
                          const SizedBox(width: AppSpacing.md),
                          StatusBadge(
                            label: isDirty ? 'Draft changes' : 'Published',
                            color: isDirty ? palette.gold : palette.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.x4l),
                    const _StatsRow(),
                    if (linkKeys.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.x4l),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.md,
                        children: [for (final key in linkKeys) _LinkIcon(linkKey: key, url: draft.links[key]!)],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.x4l),
                    const _SectionHeader(icon: Icons.rss_feed, title: 'About us'),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      draft.description.trim().isEmpty ? 'No description added yet.' : draft.description,
                      style: TextStyle(fontSize: AppType.md, color: palette.text, height: 1.6),
                    ),
                    if (draft.featured.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.x4l),
                      _SectionHeader(icon: Icons.workspace_premium_outlined, title: 'Meet our trainers', color: palette.gold),
                      const SizedBox(height: AppSpacing.md),
                      _TrainerGrid(trainers: draft.featured),
                    ],
                    _HighlightsSection(highlights: profile.highlights, canEdit: canEdit),
                    const SizedBox(height: AppSpacing.x4l),
                    _VisitUsCard(draft: draft, branches: profile.branches, canEdit: canEdit),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LinkIcon extends StatelessWidget {
  const _LinkIcon({required this.linkKey, required this.url});
  final String linkKey;
  final String url;

  @override
  Widget build(BuildContext context) {
    final meta = socialMeta[linkKey]!;
    final color = meta.colorOf(context.palette);
    return Tooltip(
      message: meta.label,
      child: Pressable(
        onTap: () => openUri(context, webUri(url)),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color.withValues(alpha: 0.25)),
            borderRadius: AppRadii.all(11),
          ),
          child: Icon(meta.icon, size: 17, color: color),
        ),
      ),
    );
  }
}

/// Two-column cards; a card opens that person's profile.
class _TrainerGrid extends StatelessWidget {
  const _TrainerGrid({required this.trainers});
  final List<DraftTrainer> trainers;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - AppSpacing.md) / 2;
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final t in trainers)
            SizedBox(
              width: width,
              child: Pressable(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TrainerCardScreen(
                        membershipId: t.membershipId, designation: t.designation.trim().isEmpty ? null : t.designation.trim()))),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    border: Border.all(color: palette.borderSoft),
                    borderRadius: AppRadii.all(AppRadii.xl),
                  ),
                  child: Column(
                    children: [
                      PersonAvatar(name: t.fullName, seed: t.membershipId, size: 44),
                      const SizedBox(height: AppSpacing.xs),
                      Text(t.fullName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.text)),
                      const SizedBox(height: 2),
                      Text(t.designation.trim().isEmpty ? 'Trainer' : t.designation.trim(),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppType.tiny, color: palette.textMuted, height: 1.4)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _VisitUsCard extends StatelessWidget {
  const _VisitUsCard({required this.draft, required this.branches, required this.canEdit});
  final ProfileDraft draft;
  final List<AcademyBranchInfo> branches;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final address = draft.fullAddress;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border.all(color: palette.borderSoft),
        borderRadius: AppRadii.all(AppRadii.xxl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(icon: Icons.location_on_outlined, title: 'Visit us', color: palette.gold),
          if (address.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(address, style: TextStyle(fontSize: AppType.base, color: palette.textMuted, height: 1.55)),
          ],
          if (draft.linkVisible('maps')) ...[
            const SizedBox(height: AppSpacing.md),
            Pressable(
              onTap: () => openUri(context, webUri(draft.links['maps']!)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new, size: 12, color: palette.primary),
                  const SizedBox(width: AppSpacing.xxs),
                  Text('Open in Google Maps', style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.bold, color: palette.primary)),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Container(height: 1, color: palette.borderSoft),
          const SizedBox(height: AppSpacing.lg),
          if (draft.contactNumber.trim().isNotEmpty)
            ContactLinkRow(icon: Icons.call_outlined, caption: 'Tap to call', value: draft.contactNumber, uri: telUri(draft.contactNumber)),
          if (draft.email.trim().isNotEmpty)
            ContactLinkRow(icon: Icons.mail_outline, caption: 'Tap to email', value: draft.email, uri: Uri(scheme: 'mailto', path: draft.email.trim())),
          if (draft.whatsapp.trim().isNotEmpty)
            ContactLinkRow(
              icon: Icons.chat_outlined,
              caption: 'Tap to chat',
              value: draft.whatsapp,
              uri: whatsappUri(draft.whatsapp),
              color: palette.paidManual,
            ),
          _BranchesSection(branches: branches, canEdit: canEdit),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.isDirty,
    required this.isPublishing,
    required this.onEdit,
    required this.onPublish,
    required this.onDiscard,
  });
  final bool isDirty;
  final bool isPublishing;
  final VoidCallback onEdit;
  final VoidCallback onPublish;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.xl + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: palette.bg, border: Border(top: BorderSide(color: palette.borderSoft))),
      child: isDirty
          ? Column(
              children: [
                AppPrimaryButton(label: 'Publish changes', icon: Icons.cloud_upload_outlined, busy: isPublishing, onPressed: isPublishing ? null : onPublish),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: OutlineActionButton(label: 'Edit', icon: Icons.edit_outlined, onTap: onEdit)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: OutlineActionButton(label: 'Discard', icon: Icons.restore, onTap: onDiscard, color: palette.notPaid)),
                  ],
                ),
              ],
            )
          : AppPrimaryButton(label: 'Edit Profile', icon: Icons.edit_outlined, onPressed: onEdit),
    );
  }
}

/// The prototype's bordered secondary button - no exact design-kit equivalent.
class OutlineActionButton extends StatelessWidget {
  const OutlineActionButton({super.key, required this.label, required this.icon, required this.onTap, this.color});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = color ?? palette.text;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(color: palette.border), borderRadius: AppRadii.all(AppRadii.xl)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: fg)),
          ],
        ),
      ),
    );
  }
}


/// A dot-indicator carousel of a highlight's photos - a real gallery feel for multiple images
/// instead of a single static picture.
class _ImageCarousel extends StatefulWidget {
  const _ImageCarousel({required this.imageUrls, this.height = 160});
  final List<String> imageUrls;
  final double height;

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (widget.imageUrls.isEmpty) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: AppRadii.all(AppRadii.lg)),
        child: Icon(Icons.image_outlined, color: palette.textFaint, size: 32),
      );
    }
    return ClipRRect(
      borderRadius: AppRadii.all(AppRadii.lg),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.imageUrls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Image.network(ApiConfig.resolveMediaUrl(widget.imageUrls[i])!, fit: BoxFit.cover, width: double.infinity),
            ),
            if (widget.imageUrls.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    widget.imageUrls.length,
                    (i) => Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? Colors.white : Colors.white.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrainerAvatarRow extends StatelessWidget {
  const _TrainerAvatarRow({required this.trainers});
  final List<HighlightTrainer> trainers;
  static const double radius = 14;

  @override
  Widget build(BuildContext context) {
    if (trainers.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    return SizedBox(
      height: radius * 2,
      child: Stack(
        children: [
          for (var i = 0; i < trainers.length && i < 4; i++)
            Positioned(
              left: i * (radius * 1.3),
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: palette.surfaceRaised, width: 2)),
                child: PersonAvatar(name: trainers[i].fullName, seed: trainers[i].membershipId, size: radius * 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _HighlightsSection extends ConsumerWidget {
  const _HighlightsSection({required this.highlights, required this.canEdit});
  final List<AcademyHighlight> highlights;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (highlights.isEmpty && !canEdit) return const SizedBox.shrink();
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.school_outlined,
            title: 'What we teach',
            trailing: canEdit
                ? Pressable(
                    onTap: () => showHighlightFormSheet(context, ref),
                    child: Row(children: [
                      Icon(Icons.add, size: 16, color: palette.primary),
                      const SizedBox(width: AppSpacing.xxs),
                      Text('Add', style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.primary)),
                    ]),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          ...highlights.map((h) => _HighlightCard(highlight: h, canEdit: canEdit)),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.highlight, required this.canEdit});
  final AcademyHighlight highlight;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Pressable(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HighlightDetailScreen(highlight: highlight, canEdit: canEdit))),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            border: Border.all(color: palette.borderSoft),
            borderRadius: AppRadii.all(AppRadii.xxl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ImageCarousel(imageUrls: highlight.imageUrls),
              const SizedBox(height: AppSpacing.md),
              Text(highlight.title, style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.text)),
              if (highlight.description != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(highlight.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppType.base, color: palette.textMuted)),
              ],
              if (highlight.trainers.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _TrainerAvatarRow(trainers: highlight.trainers),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The full detail view for one "what we teach" block - every photo, the full description, and
/// every trainer teaching it, plus (for an Admin) the edit affordances that don't fit on the
/// compact card.
class HighlightDetailScreen extends ConsumerWidget {
  const HighlightDetailScreen({super.key, required this.highlight, required this.canEdit});
  final AcademyHighlight highlight;
  final bool canEdit;

  Future<void> _addPhoto(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.bytes == null) return;
    try {
      await ref.read(academyProfileApiProvider).addHighlightImage(highlight.id, picked.bytes!, picked.name);
      ref.invalidate(academyProfileProvider);
      if (context.mounted) {
        AppNotice.success(context, 'Photo added.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Delete this highlight?',
      message: '"${highlight.title}" and its photos will be permanently removed.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await ref.read(academyProfileApiProvider).deleteHighlight(highlight.id);
      ref.invalidate(academyProfileProvider);
      if (context.mounted) {
        AppNotice.success(context, 'Deleted.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: Text(highlight.title),
        actions: canEdit
            ? [
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => showHighlightFormSheet(context, ref, existing: highlight)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, ref)),
              ]
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          _ImageCarousel(imageUrls: highlight.imageUrls, height: 240),
          if (canEdit) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Pressable(
                onTap: () => _addPhoto(context, ref),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_a_photo_outlined, size: 16, color: palette.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Text('Add photo', style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.primary)),
                ]),
              ),
            ),
          ],
          if (highlight.description != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(highlight.description!, style: TextStyle(fontSize: AppType.xl, color: palette.text, height: 1.5)),
          ],
          if (highlight.trainers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.x5l),
            Text('Taught by', style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.text)),
            const SizedBox(height: AppSpacing.md),
            ...highlight.trainers.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(children: [
                    PersonAvatar(name: t.fullName, seed: t.membershipId, size: 40),
                    const SizedBox(width: AppSpacing.md),
                    Text(t.fullName, style: TextStyle(fontSize: AppType.xl, color: palette.text)),
                  ]),
                )),
          ],
        ],
      ),
    );
  }
}

class _BranchesSection extends ConsumerWidget {
  const _BranchesSection({required this.branches, required this.canEdit});
  final List<AcademyBranchInfo> branches;
  final bool canEdit;

  Future<void> _addBranch(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New branch', style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Branch name')),
            const SizedBox(height: 12),
            TextField(controller: addressController, decoration: const InputDecoration(labelText: 'Address (optional)'), maxLines: 2),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  AppNotice.error(sheetContext, 'Give this branch a name.');
                  return;
                }
                try {
                  await ref.read(academyProfileApiProvider).addBranch(
                        name: nameController.text.trim(),
                        address: addressController.text.trim().isEmpty ? null : addressController.text.trim(),
                      );
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop(true);
                } on ApiException catch (e) {
                  if (sheetContext.mounted) AppNotice.error(sheetContext, e.message);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      ref.invalidate(academyProfileProvider);
      if (context.mounted) AppNotice.success(context, 'Branch added.');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AcademyBranchInfo branch) async {
    try {
      await ref.read(academyProfileApiProvider).deleteBranch(branch.id);
      ref.invalidate(academyProfileProvider);
      if (context.mounted) AppNotice.success(context, 'Removed.');
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (branches.isEmpty && !canEdit) return const SizedBox.shrink();
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Branches', style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text)),
              if (canEdit)
                Pressable(
                  onTap: () => _addBranch(context, ref),
                  child: Row(children: [
                    Icon(Icons.add, size: 15, color: palette.primary),
                    const SizedBox(width: AppSpacing.xxs),
                    Text('Add', style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.primary)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ...branches.map((b) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.store_mall_directory_outlined, size: 16, color: palette.textFaint),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: b.name,
                          style: TextStyle(fontWeight: AppType.bold, fontSize: AppType.base, color: palette.text),
                          children: b.address != null
                              ? [TextSpan(text: ' - ${b.address}', style: TextStyle(fontWeight: AppType.regular, color: palette.textMuted))]
                              : [],
                        ),
                      ),
                    ),
                    if (canEdit) Pressable(onTap: () => _delete(context, ref, b), child: Icon(Icons.close, size: 16, color: palette.textFaint)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// Create/edit sheet for a "what we teach" highlight - title, description, a photo carousel
/// (managed from the detail page, not here), and which trainer(s)/Admin teach it.
Future<void> showHighlightFormSheet(BuildContext context, WidgetRef ref, {AcademyHighlight? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _HighlightFormSheet(existing: existing),
  );
}

class _HighlightFormSheet extends ConsumerStatefulWidget {
  const _HighlightFormSheet({this.existing});
  final AcademyHighlight? existing;

  @override
  ConsumerState<_HighlightFormSheet> createState() => _HighlightFormSheetState();
}

class _HighlightFormSheetState extends ConsumerState<_HighlightFormSheet> {
  late final _titleController = TextEditingController(text: widget.existing?.title);
  late final _descriptionController = TextEditingController(text: widget.existing?.description);
  late final Set<String> _selectedTrainerIds = Set.of(widget.existing?.trainers.map((t) => t.membershipId) ?? const <String>[]);
  bool _isSaving = false;
  List<TrainerCandidate>? _candidates;
  String? _loadError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    try {
      final candidates = await ref.read(academyProfileApiProvider).listTrainerCandidates();
      if (mounted) setState(() => _candidates = candidates);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      AppNotice.error(context, 'Give this highlight a title.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await ref.read(academyProfileApiProvider).updateHighlight(
              highlightId: widget.existing!.id,
              title: _titleController.text.trim(),
              description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
              trainerMembershipIds: _selectedTrainerIds,
            );
      } else {
        await ref.read(academyProfileApiProvider).addHighlight(
              title: _titleController.text.trim(),
              description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
              trainerMembershipIds: _selectedTrainerIds,
            );
      }
      ref.invalidate(academyProfileProvider);
      if (mounted) {
        AppNotice.success(context, _isEditing ? 'Highlight updated.' : 'Highlight added.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEditing ? 'Edit highlight' : 'New course highlight', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Text('Trainers teaching this', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_loadError != null)
              Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12.5))
            else if (_candidates == null)
              const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_candidates!.isEmpty)
              const Text('No trainers registered yet.', style: TextStyle(fontSize: 12.5))
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _candidates!.map((c) {
                  final selected = _selectedTrainerIds.contains(c.membershipId);
                  return FilterChip(
                    label: Text(c.fullName),
                    selected: selected,
                    onSelected: (v) => setState(() => v ? _selectedTrainerIds.add(c.membershipId) : _selectedTrainerIds.remove(c.membershipId)),
                  );
                }).toList(),
              ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEditing ? 'Save changes' : 'Add highlight'),
            ),
          ],
        ),
      ),
    );
  }
}
