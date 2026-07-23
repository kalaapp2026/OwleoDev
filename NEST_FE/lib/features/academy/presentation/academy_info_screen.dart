import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/core/widgets/avatar.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';
import 'package:nest_fe/features/academy/data/academy_profile_api.dart';
import 'package:url_launcher/url_launcher.dart';

final academyProfileApiProvider = Provider((ref) => AcademyProfileApi(ref.watch(dioClientProvider)));

final academyProfileProvider = FutureProvider.autoDispose<AcademyProfile>((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(academyProfileApiProvider).getProfile();
});

Future<void> _openUrl(BuildContext context, String? url) async {
  if (url == null || url.isEmpty) return;
  final resolved = url.startsWith('http://') || url.startsWith('https://') ? url : 'https://$url';
  if (!await launchUrl(Uri.parse(resolved), mode: LaunchMode.externalApplication)) {
    if (context.mounted) AppNotice.error(context, 'Could not open this link.');
  }
}

/// About-Us page (PRD 3.10) - a single public-facing profile per academy. Everyone can read it;
/// only an Academy Admin sees the edit affordances (ABOUT_US_EDIT is non-delegable, so a Trainer
/// never gets them either).
class AcademyInfoScreen extends ConsumerWidget {
  const AcademyInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final canEdit = user != null && (user.isSuperAdmin || user.isActiveAcademyAdmin);
    final profileAsync = ref.watch(academyProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('About Institute')),
      body: AsyncValueView<AcademyProfile>(
        value: profileAsync,
        onRetry: () => ref.invalidate(academyProfileProvider),
        data: (context, profile) => _AboutInstituteView(profile: profile, canEdit: canEdit),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, this.trailing});
  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        trailing ?? const SizedBox.shrink(),
      ],
    );
  }
}

class _AboutInstituteView extends ConsumerWidget {
  const _AboutInstituteView({required this.profile, required this.canEdit});
  final AcademyProfile profile;
  final bool canEdit;

  Future<void> _changeLogo(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.bytes == null) return;
    try {
      await ref.read(academyProfileApiProvider).uploadLogo(picked.bytes!, picked.name);
      ref.invalidate(academyProfileProvider);
      if (context.mounted) AppNotice.success(context, 'Logo updated.');
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasContactInfo = profile.address != null ||
        profile.email != null ||
        profile.contactNumber != null ||
        profile.branches.isNotEmpty;
    final hasSocials = profile.instagramUrl != null || profile.xUrl != null || profile.facebookUrl != null || profile.youtubeUrl != null;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(academyProfileProvider),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Hero: a soft gradient backdrop behind the logo/name/tagline instead of a bare white
          // header, so the page reads like a real institute profile rather than a settings form.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colorScheme.primaryContainer.withValues(alpha: 0.55), colorScheme.surface],
              ),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    Avatar(name: profile.name, imageUrl: profile.logoUrl, radius: 48),
                    if (canEdit)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: InkWell(
                          onTap: () => _changeLogo(context, ref),
                          borderRadius: BorderRadius.circular(16),
                          child: CircleAvatar(
                            radius: 15,
                            backgroundColor: colorScheme.primary,
                            child: Icon(Icons.camera_alt, size: 15, color: colorScheme.onPrimary),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(profile.name, style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                if (profile.tagline != null) ...[
                  const SizedBox(height: 4),
                  Text(profile.tagline!, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                ],
                if (canEdit) ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => showEditProfileSheet(context, ref, profile: profile),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit details'),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (profile.description != null) ...[
                  Text(profile.description!, style: textTheme.bodyLarge?.copyWith(height: 1.4)),
                  const SizedBox(height: 18),
                ],
                if (profile.establishedBy != null || profile.ownerName != null) ...[
                  Wrap(
                    spacing: 28,
                    runSpacing: 10,
                    children: [
                      if (profile.establishedBy != null) _LabelledValue(label: 'Established by', value: profile.establishedBy!),
                      if (profile.ownerName != null) _LabelledValue(label: 'Owner', value: profile.ownerName!),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                if (profile.additionalInfo != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(profile.additionalInfo!, style: textTheme.bodyMedium?.copyWith(height: 1.4)),
                  ),
                  const SizedBox(height: 8),
                ],
                _HighlightsSection(highlights: profile.highlights, canEdit: canEdit),
                _FeaturedTrainersSection(trainers: profile.featuredTrainers, canEdit: canEdit),
                if (hasSocials) ...[
                  const SizedBox(height: 28),
                  Center(
                    child: Wrap(
                      spacing: 12,
                      children: [
                        if (profile.instagramUrl != null)
                          _SocialButton(icon: Icons.camera_alt_outlined, label: 'Instagram', onTap: () => _openUrl(context, profile.instagramUrl)),
                        if (profile.xUrl != null) _SocialButton(icon: Icons.alternate_email, label: 'X', onTap: () => _openUrl(context, profile.xUrl)),
                        if (profile.facebookUrl != null)
                          _SocialButton(icon: Icons.facebook_outlined, label: 'Facebook', onTap: () => _openUrl(context, profile.facebookUrl)),
                        if (profile.youtubeUrl != null)
                          _SocialButton(
                              icon: Icons.smart_display_outlined, label: 'YouTube', onTap: () => _openUrl(context, profile.youtubeUrl)),
                      ],
                    ),
                  ),
                ],
                if (hasContactInfo || canEdit) ...[
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeader(icon: Icons.contact_page_outlined, title: 'Contact'),
                        const SizedBox(height: 12),
                        if (profile.address != null) _ContactRow(icon: Icons.location_on_outlined, text: profile.address!),
                        if (profile.email != null) _ContactRow(icon: Icons.mail_outline, text: profile.email!),
                        if (profile.contactNumber != null) _ContactRow(icon: Icons.call_outlined, text: profile.contactNumber!),
                        _BranchesSection(branches: profile.branches, canEdit: canEdit),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _LabelledValue extends StatelessWidget {
  const _LabelledValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.6, color: colorScheme.outline, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        ],
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
    final colorScheme = Theme.of(context).colorScheme;
    if (widget.imageUrls.isEmpty) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.image_outlined, color: colorScheme.outline, size: 32),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
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
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    widget.imageUrls.length,
                    (i) => Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      ),
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
    return SizedBox(
      height: radius * 2,
      child: Stack(
        children: [
          for (var i = 0; i < trainers.length && i < 4; i++)
            Positioned(
              left: i * (radius * 1.3),
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2)),
                child: Avatar(name: trainers[i].fullName, imageUrl: trainers[i].profileImageUrl, radius: radius),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.school_outlined,
            title: 'What we teach',
            trailing: canEdit
                ? TextButton.icon(
                    onPressed: () => showHighlightFormSheet(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  )
                : null,
          ),
          const SizedBox(height: 10),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => HighlightDetailScreen(highlight: highlight, canEdit: canEdit),
        )),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ImageCarousel(imageUrls: highlight.imageUrls),
              const SizedBox(height: 10),
              Text(highlight.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (highlight.description != null) ...[
                const SizedBox(height: 4),
                Text(highlight.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (highlight.trainers.isNotEmpty) ...[
                const SizedBox(height: 10),
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
    final confirmed = await AppNotice.confirm(
      context,
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
    return Scaffold(
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
        padding: const EdgeInsets.all(20),
        children: [
          _ImageCarousel(imageUrls: highlight.imageUrls, height: 240),
          if (canEdit) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => _addPhoto(context, ref), icon: const Icon(Icons.add_a_photo_outlined, size: 16), label: const Text('Add photo')),
            ),
          ],
          if (highlight.description != null) ...[
            const SizedBox(height: 12),
            Text(highlight.description!, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
          ],
          if (highlight.trainers.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Taught by', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            ...highlight.trainers.map((t) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(name: t.fullName, imageUrl: t.profileImageUrl, radius: 22),
                  title: Text(t.fullName),
                )),
          ],
        ],
      ),
    );
  }
}

class _FeaturedTrainersSection extends ConsumerWidget {
  const _FeaturedTrainersSection({required this.trainers, required this.canEdit});
  final List<FeaturedTrainer> trainers;
  final bool canEdit;

  Future<void> _pickTrainer(BuildContext context, WidgetRef ref) async {
    List<TrainerCandidate> candidates;
    try {
      candidates = await ref.read(academyProfileApiProvider).listTrainerCandidates();
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
      return;
    }
    final featuredIds = trainers.map((t) => t.trainerMembershipId).toSet();
    final available = candidates.where((c) => !featuredIds.contains(c.membershipId)).toList();
    if (!context.mounted) return;
    if (available.isEmpty) {
      AppNotice.error(context, 'Every Trainer/Admin is already featured.');
      return;
    }

    final picked = await showModalBottomSheet<TrainerCandidate>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: available
              .map((c) => ListTile(
                    leading: Avatar(name: c.fullName, imageUrl: c.profileImageUrl, radius: 18),
                    title: Text(c.fullName),
                    onTap: () => Navigator.of(sheetContext).pop(c),
                  ))
              .toList(),
        ),
      ),
    );
    if (picked == null) return;
    try {
      await ref.read(academyProfileApiProvider).addFeaturedTrainer(picked.membershipId);
      ref.invalidate(academyProfileProvider);
      if (context.mounted) AppNotice.success(context, '${picked.fullName} added.');
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, FeaturedTrainer trainer) async {
    try {
      await ref.read(academyProfileApiProvider).deleteFeaturedTrainer(trainer.id);
      ref.invalidate(academyProfileProvider);
      if (context.mounted) AppNotice.success(context, 'Removed.');
    } on ApiException catch (e) {
      if (context.mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (trainers.isEmpty && !canEdit) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.groups_2_outlined,
            title: 'Meet our trainers',
            trailing: canEdit
                ? TextButton.icon(
                    onPressed: () => _pickTrainer(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 14,
            children: trainers
                .map((t) => SizedBox(
                      width: 84,
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Avatar(name: t.fullName, imageUrl: t.profileImageUrl, radius: 32),
                              if (canEdit)
                                Positioned(
                                  right: -4,
                                  top: -4,
                                  child: InkWell(
                                    onTap: () => _remove(context, ref, t),
                                    child: CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Theme.of(context).colorScheme.error,
                                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(t.fullName, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
                        ],
                      ),
                    ))
                .toList(),
          ),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Branches', style: Theme.of(context).textTheme.labelLarge),
              if (canEdit)
                TextButton.icon(
                  onPressed: () => _addBranch(context, ref),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ...branches.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 6, top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.store_mall_directory_outlined, size: 18, color: colorScheme.outline),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: b.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          children: b.address != null
                              ? [TextSpan(text: ' - ${b.address}', style: const TextStyle(fontWeight: FontWeight.normal))]
                              : [],
                        ),
                      ),
                    ),
                    if (canEdit)
                      InkWell(onTap: () => _delete(context, ref, b), child: Icon(Icons.close, size: 16, color: colorScheme.outline)),
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
  late final Set<String> _selectedTrainerIds =
      Set.of(widget.existing?.trainers.map((t) => t.membershipId) ?? const <String>[]);
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

/// Consolidated edit form for every singleton About-Us field (everything except logo, which has
/// its own tap-to-change affordance on the avatar, and highlights/trainers/branches, which are
/// their own repeatable lists with their own add/remove controls).
Future<void> showEditProfileSheet(BuildContext context, WidgetRef ref, {required AcademyProfile profile}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EditProfileSheet(profile: profile),
  );
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});
  final AcademyProfile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _taglineController = TextEditingController(text: widget.profile.tagline);
  late final _descriptionController = TextEditingController(text: widget.profile.description);
  late final _establishedByController = TextEditingController(text: widget.profile.establishedBy);
  late final _ownerController = TextEditingController(text: widget.profile.ownerName);
  late final _additionalInfoController = TextEditingController(text: widget.profile.additionalInfo);
  late final _addressController = TextEditingController(text: widget.profile.address);
  late final _contactController = TextEditingController(text: widget.profile.contactNumber);
  late final _emailController = TextEditingController(text: widget.profile.email);
  late final _instagramController = TextEditingController(text: widget.profile.instagramUrl);
  late final _xController = TextEditingController(text: widget.profile.xUrl);
  late final _facebookController = TextEditingController(text: widget.profile.facebookUrl);
  late final _youtubeController = TextEditingController(text: widget.profile.youtubeUrl);
  bool _isSaving = false;

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(academyProfileApiProvider).updateProfile(
            tagline: _taglineController.text.trim(),
            description: _descriptionController.text.trim(),
            establishedBy: _establishedByController.text.trim(),
            ownerName: _ownerController.text.trim(),
            additionalInfo: _additionalInfoController.text.trim(),
            address: _addressController.text.trim(),
            contactNumber: _contactController.text.trim(),
            email: _emailController.text.trim(),
            instagramUrl: _instagramController.text.trim(),
            xUrl: _xController.text.trim(),
            facebookUrl: _facebookController.text.trim(),
            youtubeUrl: _youtubeController.text.trim(),
          );
      ref.invalidate(academyProfileProvider);
      if (mounted) {
        AppNotice.success(context, 'About Institute updated.');
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
            Text('Edit details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Leave a field blank to hide it from the page.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            TextField(controller: _taglineController, decoration: const InputDecoration(labelText: 'Tagline')),
            const SizedBox(height: 12),
            TextField(controller: _descriptionController, decoration: const InputDecoration(labelText: 'Description'), maxLines: 4),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(controller: _establishedByController, decoration: const InputDecoration(labelText: 'Established by')),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _ownerController, decoration: const InputDecoration(labelText: 'Owner'))),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _additionalInfoController, decoration: const InputDecoration(labelText: 'Additional info'), maxLines: 3),
            const SizedBox(height: 16),
            Text('Contact', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(controller: _addressController, decoration: const InputDecoration(labelText: 'Address'), maxLines: 2),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: _contactController, decoration: const InputDecoration(labelText: 'Phone number'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email'))),
              ],
            ),
            const SizedBox(height: 16),
            Text('Social links', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(controller: _instagramController, decoration: const InputDecoration(labelText: 'Instagram')),
            const SizedBox(height: 12),
            TextField(controller: _xController, decoration: const InputDecoration(labelText: 'X (Twitter)')),
            const SizedBox(height: 12),
            TextField(controller: _facebookController, decoration: const InputDecoration(labelText: 'Facebook')),
            const SizedBox(height: 12),
            TextField(controller: _youtubeController, decoration: const InputDecoration(labelText: 'YouTube')),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
