import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/core/design/status_badge.dart';
import 'package:nest_fe/core/design/toast.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';
import 'package:nest_fe/features/academy/data/academy_profile_api.dart';
import 'package:nest_fe/features/academy/presentation/trainer_card_screen.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/dashboard/data/dashboard_api.dart';
import 'package:url_launcher/url_launcher.dart';

final academyProfileApiProvider = Provider((ref) => AcademyProfileApi(ref.watch(dioClientProvider)));

final academyProfileProvider = FutureProvider.autoDispose<AcademyProfile>((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(academyProfileApiProvider).getProfile();
});

Future<void> _openUrl(BuildContext context, String? url) async {
  if (url == null || url.trim().isEmpty) return;
  final resolved = url.startsWith('http://') || url.startsWith('https://') ? url : 'https://$url';
  if (!await launchUrl(Uri.parse(resolved), mode: LaunchMode.externalApplication)) {
    if (context.mounted) AppNotice.error(context, 'Could not open this link.');
  }
}

/// The five toggleable social platforms plus Maps (edited under Location, but sharing the same
/// on/off + URL mechanics). Kept as a plain map of metadata, mirroring the JSX prototype's
/// SOCIAL_META, so every row/icon renders off one source of truth.
class _SocialMeta {
  const _SocialMeta({required this.label, required this.icon, required this.colorOf, required this.hint});
  final String label;
  final IconData icon;
  final Color Function(AppPalette) colorOf;
  final String hint;
}

const _socialMeta = <String, _SocialMeta>{
  'instagram': _SocialMeta(
      label: 'Instagram', icon: Icons.camera_alt_outlined, colorOf: _magenta, hint: 'instagram.com/yourpage'),
  'x': _SocialMeta(label: 'X (Twitter)', icon: Icons.alternate_email, colorOf: _violet, hint: 'x.com/yourpage'),
  'facebook': _SocialMeta(
      label: 'Facebook', icon: Icons.facebook_outlined, colorOf: _gateway, hint: 'facebook.com/yourpage'),
  'youtube': _SocialMeta(
      label: 'YouTube', icon: Icons.smart_display_outlined, colorOf: _notPaid, hint: 'youtube.com/@yourchannel'),
  'website':
      _SocialMeta(label: 'Website', icon: Icons.language_outlined, colorOf: _primary, hint: 'www.youracademy.com'),
  'maps':
      _SocialMeta(label: 'Google Location', icon: Icons.map_outlined, colorOf: _gold, hint: 'maps.app.goo.gl/...'),
};

Color _magenta(AppPalette p) => p.magenta;
Color _violet(AppPalette p) => p.violet;
Color _gateway(AppPalette p) => p.gateway;
Color _notPaid(AppPalette p) => p.notPaid;
Color _primary(AppPalette p) => p.primary;
Color _gold(AppPalette p) => p.gold;

/// The editable fields of the About-Us profile, held locally as a "draft" until Publish - the
/// JSX prototype's core idea, reimplemented on top of the app's real, always-live endpoints rather
/// than a backend draft table (see the plan's "Scope boundary" note). Featured trainers,
/// highlights and branches are deliberately NOT part of this draft: they stay immediate writes,
/// same as today.
class _ProfileDraft {
  _ProfileDraft({
    required this.tagline,
    required this.description,
    required this.establishedBy,
    required this.ownerName,
    required this.additionalInfo,
    required this.address,
    required this.contactNumber,
    required this.email,
    required this.instagramUrl,
    required this.xUrl,
    required this.facebookUrl,
    required this.youtubeUrl,
    required this.whatsapp,
    required this.websiteUrl,
    required this.mapsUrl,
  });

  factory _ProfileDraft.from(AcademyProfile p) => _ProfileDraft(
        tagline: p.tagline ?? '',
        description: p.description ?? '',
        establishedBy: p.establishedBy ?? '',
        ownerName: p.ownerName ?? '',
        additionalInfo: p.additionalInfo ?? '',
        address: p.address ?? '',
        contactNumber: p.contactNumber ?? '',
        email: p.email ?? '',
        instagramUrl: p.instagramUrl ?? '',
        xUrl: p.xUrl ?? '',
        facebookUrl: p.facebookUrl ?? '',
        youtubeUrl: p.youtubeUrl ?? '',
        whatsapp: p.whatsapp ?? '',
        websiteUrl: p.websiteUrl ?? '',
        mapsUrl: p.mapsUrl ?? '',
      );

  String tagline;
  String description;
  String establishedBy;
  String ownerName;
  String additionalInfo;
  String address;
  String contactNumber;
  String email;
  String instagramUrl;
  String xUrl;
  String facebookUrl;
  String youtubeUrl;
  String whatsapp;
  String websiteUrl;
  String mapsUrl;

  String urlFor(String key) => switch (key) {
        'instagram' => instagramUrl,
        'x' => xUrl,
        'facebook' => facebookUrl,
        'youtube' => youtubeUrl,
        'website' => websiteUrl,
        'maps' => mapsUrl,
        _ => '',
      };

  void setUrlFor(String key, String value) {
    switch (key) {
      case 'instagram':
        instagramUrl = value;
      case 'x':
        xUrl = value;
      case 'facebook':
        facebookUrl = value;
      case 'youtube':
        youtubeUrl = value;
      case 'website':
        websiteUrl = value;
      case 'maps':
        mapsUrl = value;
    }
  }

  bool equalsProfile(AcademyProfile p) =>
      tagline == (p.tagline ?? '') &&
      description == (p.description ?? '') &&
      establishedBy == (p.establishedBy ?? '') &&
      ownerName == (p.ownerName ?? '') &&
      additionalInfo == (p.additionalInfo ?? '') &&
      address == (p.address ?? '') &&
      contactNumber == (p.contactNumber ?? '') &&
      email == (p.email ?? '') &&
      instagramUrl == (p.instagramUrl ?? '') &&
      xUrl == (p.xUrl ?? '') &&
      facebookUrl == (p.facebookUrl ?? '') &&
      youtubeUrl == (p.youtubeUrl ?? '') &&
      whatsapp == (p.whatsapp ?? '') &&
      websiteUrl == (p.websiteUrl ?? '') &&
      mapsUrl == (p.mapsUrl ?? '');
}

/// About-Us page (PRD 3.10) - a single public-facing profile per academy. Everyone can read it;
/// only an Academy Admin sees the edit affordances (ABOUT_US_EDIT is non-delegable, so a Trainer
/// never gets them either).
///
/// The view screen always renders the DRAFT - edits stay local until Publish, matching the JSX
/// prototype's "view doubles as preview" design - while highlights/branches/featured-trainers
/// (repeatable child resources with their own add/remove semantics) stay immediate writes.
class AcademyInfoScreen extends ConsumerStatefulWidget {
  const AcademyInfoScreen({super.key});

  @override
  ConsumerState<AcademyInfoScreen> createState() => _AcademyInfoScreenState();
}

class _AcademyInfoScreenState extends ConsumerState<AcademyInfoScreen> {
  _ProfileDraft? _draft;
  Uint8List? _pendingLogoBytes;
  String? _pendingLogoName;
  Uint8List? _pendingCoverBytes;
  String? _pendingCoverName;
  final Set<String> _disabledSocialKeys = {};
  bool _isPublishing = false;

  void _ensureDraft(AcademyProfile profile) {
    _draft ??= _ProfileDraft.from(profile);
  }

  bool _isDirty(AcademyProfile profile) {
    final draft = _draft;
    if (draft == null) return false;
    return !draft.equalsProfile(profile) || _pendingLogoBytes != null || _pendingCoverBytes != null || _disabledSocialKeys.isNotEmpty;
  }

  Future<void> _openEdit(AcademyProfile profile) async {
    _ensureDraft(profile);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _EditProfileScreen(
        profile: profile,
        draft: _draft!,
        disabledSocialKeys: _disabledSocialKeys,
        initialLogoBytes: _pendingLogoBytes,
        initialLogoName: _pendingLogoName,
        initialCoverBytes: _pendingCoverBytes,
        initialCoverName: _pendingCoverName,
        onLogoChanged: (bytes, name) => setState(() {
          _pendingLogoBytes = bytes;
          _pendingLogoName = name;
        }),
        onCoverChanged: (bytes, name) => setState(() {
          _pendingCoverBytes = bytes;
          _pendingCoverName = name;
        }),
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _publish(AcademyProfile profile) async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _isPublishing = true);
    try {
      final api = ref.read(academyProfileApiProvider);
      if (_pendingLogoBytes != null) {
        await api.uploadLogo(_pendingLogoBytes!, _pendingLogoName ?? 'logo.jpg');
      }
      if (_pendingCoverBytes != null) {
        await api.uploadCoverImage(_pendingCoverBytes!, _pendingCoverName ?? 'cover.jpg');
      }
      String urlOrBlank(String key, String value) => _disabledSocialKeys.contains(key) ? '' : value;
      await api.updateProfile(
        tagline: draft.tagline,
        description: draft.description,
        establishedBy: draft.establishedBy,
        ownerName: draft.ownerName,
        additionalInfo: draft.additionalInfo,
        address: draft.address,
        contactNumber: draft.contactNumber,
        email: draft.email,
        instagramUrl: urlOrBlank('instagram', draft.instagramUrl),
        xUrl: urlOrBlank('x', draft.xUrl),
        facebookUrl: urlOrBlank('facebook', draft.facebookUrl),
        youtubeUrl: urlOrBlank('youtube', draft.youtubeUrl),
        whatsapp: draft.whatsapp,
        websiteUrl: urlOrBlank('website', draft.websiteUrl),
        mapsUrl: urlOrBlank('maps', draft.mapsUrl),
      );
      _draft = null;
      _pendingLogoBytes = null;
      _pendingLogoName = null;
      _pendingCoverBytes = null;
      _pendingCoverName = null;
      _disabledSocialKeys.clear();
      ref.invalidate(academyProfileProvider);
      if (mounted) showAppToast(context, 'Academy profile published.');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<void> _discard() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Discard draft changes?',
      message: "Your edits will be reverted back to the last published version of the profile. This can't be undone.",
      confirmLabel: 'Discard',
    );
    if (!confirmed) return;
    setState(() {
      _draft = null;
      _pendingLogoBytes = null;
      _pendingLogoName = null;
      _pendingCoverBytes = null;
      _pendingCoverName = null;
      _disabledSocialKeys.clear();
    });
    if (mounted) showAppToast(context, 'Draft changes discarded.');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final user = ref.watch(sessionControllerProvider).user;
    final canEdit = user != null && (user.isSuperAdmin || user.isActiveAcademyAdmin);
    final profileAsync = ref.watch(academyProfileProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(title: const Text('Academy Profile')),
      body: AsyncValueView<AcademyProfile>(
        value: profileAsync,
        onRetry: () => ref.invalidate(academyProfileProvider),
        data: (context, profile) {
          _ensureDraft(profile);
          return _ProfileViewScreen(
            profile: profile,
            draft: _draft!,
            canEdit: canEdit,
            isDirty: _isDirty(profile),
            isPublishing: _isPublishing,
            pendingLogoBytes: _pendingLogoBytes,
            pendingCoverBytes: _pendingCoverBytes,
            disabledSocialKeys: _disabledSocialKeys,
            onEdit: () => _openEdit(profile),
            onPublish: () => _publish(profile),
            onDiscard: _discard,
          );
        },
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
    final palette = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: palette.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(title, style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.bold, color: palette.text)),
          ],
        ),
        trailing ?? const SizedBox.shrink(),
      ],
    );
  }
}

/// Students/Trainers/Courses, reusing the same /dashboard/stats endpoint the ERP Dashboard's own
/// stats row reads, so the two screens can never disagree on the numbers. Courses specifically
/// reuses activeCoursesProvider rather than the endpoint's own course count, matching the
/// Dashboard's own precedent for the same reason.
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
        Expanded(child: _StatTile(icon: Icons.groups_outlined, value: studentCount, label: 'Students', color: palette.primary)),
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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.sm),
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
          Text(value, style: TextStyle(fontSize: AppType.x4l, fontWeight: AppType.heavy, color: palette.text, letterSpacing: -0.3)),
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

/// The view screen: renders the DRAFT (not necessarily what's live) for `_ProfileDraft`-covered
/// fields, and the real, immediately-written data for name/logo-fallback/highlights/branches/
/// featured trainers.
class _ProfileViewScreen extends StatelessWidget {
  const _ProfileViewScreen({
    required this.profile,
    required this.draft,
    required this.canEdit,
    required this.isDirty,
    required this.isPublishing,
    required this.pendingLogoBytes,
    required this.pendingCoverBytes,
    required this.disabledSocialKeys,
    required this.onEdit,
    required this.onPublish,
    required this.onDiscard,
  });

  final AcademyProfile profile;
  final _ProfileDraft draft;
  final bool canEdit;
  final bool isDirty;
  final bool isPublishing;
  final Uint8List? pendingLogoBytes;
  final Uint8List? pendingCoverBytes;
  final Set<String> disabledSocialKeys;
  final VoidCallback onEdit;
  final VoidCallback onPublish;
  final VoidCallback onDiscard;

  bool _socialVisible(String key) => !disabledSocialKeys.contains(key) && draft.urlFor(key).trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final socialKeys = ['instagram', 'facebook', 'youtube', 'website', 'x', 'maps'].where(_socialVisible).toList();

    return Column(
      children: [
        if (isDirty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: AppSpacing.sm),
            color: palette.goldSoft,
            child: Row(
              children: [
                Icon(Icons.visibility_off_outlined, size: 13, color: palette.gold),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Only you can see this — everyone else still sees the published version.',
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
              _HeroBlock(
                name: profile.name,
                logoUrl: profile.logoUrl,
                coverUrl: profile.coverImageUrl,
                pendingLogoBytes: pendingLogoBytes,
                pendingCoverBytes: pendingCoverBytes,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.x4l, AppSpacing.page, AppSpacing.page),
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
                              Text(profile.name,
                                  style: TextStyle(fontSize: AppType.title, fontWeight: AppType.heavy, color: palette.text, letterSpacing: -0.3)),
                              if (draft.tagline.trim().isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.xxs),
                                Text(draft.tagline, style: TextStyle(fontSize: AppType.md, color: palette.textMuted)),
                              ],
                            ],
                          ),
                        ),
                        StatusBadge(
                          label: isDirty ? 'Draft changes' : 'Published',
                          color: isDirty ? palette.gold : palette.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.x4l),
                    const _StatsRow(),
                    if (socialKeys.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.x4l),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.md,
                        children: socialKeys.map((key) {
                          final meta = _socialMeta[key]!;
                          final color = meta.colorOf(palette);
                          return Pressable(
                            onTap: () => _openUrl(context, draft.urlFor(key)),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                border: Border.all(color: color.withValues(alpha: 0.25)),
                                borderRadius: AppRadii.all(AppRadii.lg),
                              ),
                              child: Icon(meta.icon, size: 17, color: color),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.x4l),
                    Row(
                      children: [
                        Icon(Icons.rss_feed, size: 13, color: palette.primary),
                        const SizedBox(width: AppSpacing.xs),
                        Text('About us', style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.text)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      draft.description.trim().isEmpty ? 'No description added yet.' : draft.description,
                      style: TextStyle(fontSize: AppType.lg, color: palette.textMuted, height: 1.5),
                    ),
                    _FeaturedTrainersSection(trainers: profile.featuredTrainers, canEdit: canEdit),
                    _HighlightsSection(highlights: profile.highlights, canEdit: canEdit),
                    const SizedBox(height: AppSpacing.x4l),
                    Container(
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
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 13, color: palette.gold),
                              const SizedBox(width: AppSpacing.xs),
                              Text('Visit us', style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.text)),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (draft.address.trim().isNotEmpty || profile.city != null)
                            Text(
                              [draft.address.trim(), profile.city, profile.state].where((s) => s != null && s.isNotEmpty).join(', '),
                              style: TextStyle(fontSize: AppType.base, color: palette.textMuted, height: 1.5),
                            ),
                          if (_socialVisible('maps')) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Pressable(
                              onTap: () => _openUrl(context, draft.mapsUrl),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.open_in_new, size: 12, color: palette.primary),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text('Open in Google Maps',
                                      style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.bold, color: palette.primary)),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          Container(height: 1, color: palette.borderSoft),
                          const SizedBox(height: AppSpacing.lg),
                          if (draft.contactNumber.trim().isNotEmpty)
                            _ContactRow(icon: Icons.call_outlined, caption: 'Tap to call', value: draft.contactNumber, href: 'tel:${draft.contactNumber}'),
                          if (draft.email.trim().isNotEmpty)
                            _ContactRow(icon: Icons.mail_outline, caption: 'Tap to email', value: draft.email, href: 'mailto:${draft.email}'),
                          if (draft.whatsapp.trim().isNotEmpty)
                            _ContactRow(
                              icon: Icons.chat_outlined,
                              caption: 'Tap to chat',
                              value: 'Message on WhatsApp',
                              href: 'https://wa.me/${draft.whatsapp.replaceAll(RegExp(r'[^0-9]'), '')}',
                              color: palette.paidManual,
                            ),
                          _BranchesSection(branches: profile.branches, canEdit: canEdit),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _BottomActionBar(
          canEdit: canEdit,
          isDirty: isDirty,
          isPublishing: isPublishing,
          onEdit: onEdit,
          onPublish: onPublish,
          onDiscard: onDiscard,
        ),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({
    required this.name,
    required this.logoUrl,
    required this.coverUrl,
    required this.pendingLogoBytes,
    required this.pendingCoverBytes,
  });
  final String name;
  final String? logoUrl;
  final String? coverUrl;
  final Uint8List? pendingLogoBytes;
  final Uint8List? pendingCoverBytes;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const coverHeight = 148.0;
    const logoSize = 68.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: coverHeight,
          decoration: BoxDecoration(
            gradient: (pendingCoverBytes == null && coverUrl == null)
                ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [palette.primary.withValues(alpha: 0.22), palette.bg])
                : null,
          ),
          child: pendingCoverBytes != null
              ? Image.memory(pendingCoverBytes!, fit: BoxFit.cover, width: double.infinity, height: coverHeight)
              : coverUrl != null
                  ? Image.network(ApiConfig.resolveMediaUrl(coverUrl)!, fit: BoxFit.cover, width: double.infinity, height: coverHeight)
                  : null,
        ),
        Positioned(
          left: AppSpacing.page,
          top: coverHeight - logoSize / 2,
          child: _LogoMark(name: name, imageUrl: logoUrl, pendingBytes: pendingLogoBytes, size: logoSize),
        ),
      ],
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.name, required this.imageUrl, required this.pendingBytes, this.size = 68});
  final String name;
  final String? imageUrl;
  final Uint8List? pendingBytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = PersonAvatar.colorFor(name, palette);

    Widget content;
    if (pendingBytes != null) {
      content = Image.memory(pendingBytes!, fit: BoxFit.cover);
    } else if (imageUrl != null) {
      content = Image.network(ApiConfig.resolveMediaUrl(imageUrl)!, fit: BoxFit.cover);
    } else {
      content = Container(
        color: color,
        alignment: Alignment.center,
        child: Text(InitialsAvatar.initialsOf(name), style: TextStyle(fontSize: size * 0.32, fontWeight: AppType.heavy, color: Colors.white)),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(borderRadius: AppRadii.all(AppRadii.x3l), border: Border.all(color: palette.bg, width: 3), boxShadow: AppShadows.dialog),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.canEdit,
    required this.isDirty,
    required this.isPublishing,
    required this.onEdit,
    required this.onPublish,
    required this.onDiscard,
  });
  final bool canEdit;
  final bool isDirty;
  final bool isPublishing;
  final VoidCallback onEdit;
  final VoidCallback onPublish;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    if (!canEdit) return const SizedBox.shrink();
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.lg + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: palette.bg, border: Border(top: BorderSide(color: palette.borderSoft))),
      child: isDirty
          ? Column(
              children: [
                AppPrimaryButton(label: 'Publish changes', icon: Icons.cloud_upload_outlined, busy: isPublishing, onPressed: isPublishing ? null : onPublish),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: _SecondaryButton(label: 'Edit', icon: Icons.edit_outlined, onTap: onEdit)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: _SecondaryButton(label: 'Discard', icon: Icons.restore, onTap: onDiscard, color: palette.notPaid)),
                  ],
                ),
              ],
            )
          : AppPrimaryButton(label: 'Edit Profile', icon: Icons.edit_outlined, onPressed: onEdit),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.icon, required this.onTap, this.color});
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
          mainAxisAlignment: MainAxisAlignment.center,
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

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.caption, required this.value, required this.href, this.color});
  final IconData icon;
  final String caption;
  final String value;
  final String href;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = color ?? palette.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Pressable(
        onTap: () => _openUrl(context, href),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(color: palette.surfaceHigh, border: Border.all(color: palette.border), borderRadius: AppRadii.all(AppRadii.lg)),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: fg.withValues(alpha: 0.1), borderRadius: AppRadii.all(9)),
                child: Icon(icon, size: 14, color: fg),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(caption.toUpperCase(), style: TextStyle(fontSize: AppType.micro, fontWeight: AppType.bold, color: palette.textMuted, letterSpacing: 0.4)),
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: fg)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 15, color: palette.textFaint),
            ],
          ),
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

class _FeaturedTrainersSection extends ConsumerWidget {
  const _FeaturedTrainersSection({required this.trainers, required this.canEdit});
  final List<FeaturedTrainer> trainers;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (trainers.isEmpty && !canEdit) return const SizedBox.shrink();
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.groups_2_outlined, title: 'Meet our trainers'),
          const SizedBox(height: AppSpacing.md),
          if (trainers.isEmpty)
            Text('No trainers featured yet.', style: TextStyle(fontSize: AppType.base, color: palette.textFaint))
          else
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: trainers.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.lg),
                itemBuilder: (context, i) {
                  final t = trainers[i];
                  return Pressable(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => TrainerCardScreen(membershipId: t.trainerMembershipId, designation: t.designation))),
                    child: SizedBox(
                      width: 84,
                      child: Column(
                        children: [
                          PersonAvatar(name: t.fullName, seed: t.trainerMembershipId, size: 56),
                          const SizedBox(height: AppSpacing.xs),
                          Text(t.fullName, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.text)),
                          if (t.designation != null)
                            Text(t.designation!, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: AppType.tiny, color: palette.textMuted)),
                        ],
                      ),
                    ),
                  );
                },
              ),
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

/// A small on/off switch, matching the JSX prototype's rounded track-and-knob toggle - no exact
/// design-system equivalent exists ([FlipToggle] is a labelled pill, not a plain switch).
class _MiniSwitch extends StatelessWidget {
  const _MiniSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: AppMotion.fade,
        width: 42,
        height: 24,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: value ? palette.primary : palette.surfaceHigh, borderRadius: AppRadii.all(AppRadii.pill)),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: value ? palette.onPrimary : palette.textFaint)),
      ),
    );
  }
}

/// One on/off + URL row - the same shape for every social platform and Maps. [socialKey] indexes
/// into [draft.urlFor]/[draft.setUrlFor] and [disabledSocialKeys].
class _SocialToggleRow extends StatefulWidget {
  const _SocialToggleRow({required this.socialKey, required this.draft, required this.disabledSocialKeys});
  final String socialKey;
  final _ProfileDraft draft;
  final Set<String> disabledSocialKeys;

  @override
  State<_SocialToggleRow> createState() => _SocialToggleRowState();
}

class _SocialToggleRowState extends State<_SocialToggleRow> {
  late final _controller = TextEditingController(text: widget.draft.urlFor(widget.socialKey));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = _socialMeta[widget.socialKey]!;
    final color = meta.colorOf(palette);
    final enabled = !widget.disabledSocialKeys.contains(widget.socialKey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      decoration: BoxDecoration(color: palette.surfaceRaised, border: Border.all(color: palette.border), borderRadius: AppRadii.all(AppRadii.xl)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: AppRadii.all(9)),
                child: Icon(meta.icon, size: 15, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(meta.label, style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.text))),
              _MiniSwitch(
                value: enabled,
                onChanged: (v) => setState(() {
                  if (v) {
                    widget.disabledSocialKeys.remove(widget.socialKey);
                  } else {
                    widget.disabledSocialKeys.add(widget.socialKey);
                  }
                }),
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 9),
              decoration: BoxDecoration(color: palette.surfaceHigh, border: Border.all(color: palette.border), borderRadius: AppRadii.all(AppRadii.lg)),
              child: Row(
                children: [
                  Icon(Icons.link, size: 13, color: palette.textFaint),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: (v) => widget.draft.setUrlFor(widget.socialKey, v),
                      decoration: InputDecoration(border: InputBorder.none, isDense: true, hintText: meta.hint, hintStyle: TextStyle(color: palette.textFaint, fontSize: AppType.md)),
                      style: TextStyle(fontSize: AppType.md, fontWeight: AppType.medium, color: palette.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen editor for every `_ProfileDraft` field plus the logo/cover picker and the
/// immediate-write featured-trainers editor. Everything here mutates `draft`/`disabledSocialKeys`
/// in place (same object the parent holds), so popping back to the view screen reflects every
/// change without extra plumbing - only the pending image bytes need an explicit callback, since
/// re-pointing a `Uint8List?` field can't be observed through object mutation.
class _EditProfileScreen extends ConsumerStatefulWidget {
  const _EditProfileScreen({
    required this.profile,
    required this.draft,
    required this.disabledSocialKeys,
    required this.initialLogoBytes,
    required this.initialLogoName,
    required this.initialCoverBytes,
    required this.initialCoverName,
    required this.onLogoChanged,
    required this.onCoverChanged,
  });

  final AcademyProfile profile;
  final _ProfileDraft draft;
  final Set<String> disabledSocialKeys;
  final Uint8List? initialLogoBytes;
  final String? initialLogoName;
  final Uint8List? initialCoverBytes;
  final String? initialCoverName;
  final void Function(Uint8List? bytes, String? name) onLogoChanged;
  final void Function(Uint8List? bytes, String? name) onCoverChanged;

  @override
  ConsumerState<_EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<_EditProfileScreen> {
  late Uint8List? _logoBytes = widget.initialLogoBytes;
  late Uint8List? _coverBytes = widget.initialCoverBytes;
  bool _moreDetailsOpen = false;
  late bool _sameAsPhone = widget.draft.whatsapp.isNotEmpty && widget.draft.whatsapp == widget.draft.contactNumber;

  late final _taglineController = TextEditingController(text: widget.draft.tagline);
  late final _descriptionController = TextEditingController(text: widget.draft.description);
  late final _establishedByController = TextEditingController(text: widget.draft.establishedBy);
  late final _ownerController = TextEditingController(text: widget.draft.ownerName);
  late final _additionalInfoController = TextEditingController(text: widget.draft.additionalInfo);
  late final _addressController = TextEditingController(text: widget.draft.address);
  late final _contactController = TextEditingController(text: widget.draft.contactNumber);
  late final _emailController = TextEditingController(text: widget.draft.email);
  late final _whatsappController = TextEditingController(text: widget.draft.whatsapp);

  @override
  void dispose() {
    _taglineController.dispose();
    _descriptionController.dispose();
    _establishedByController.dispose();
    _ownerController.dispose();
    _additionalInfoController.dispose();
    _addressController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (!mounted || result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    setState(() => _logoBytes = f.bytes);
    widget.onLogoChanged(f.bytes, f.name);
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (!mounted || result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    setState(() => _coverBytes = f.bytes);
    widget.onCoverChanged(f.bytes, f.name);
  }

  void _cancelPendingLogo() {
    setState(() => _logoBytes = null);
    widget.onLogoChanged(null, null);
  }

  void _cancelPendingCover() {
    setState(() => _coverBytes = null);
    widget.onCoverChanged(null, null);
  }

  Future<void> _addFeaturedTrainer() async {
    List<TrainerCandidate> candidates;
    try {
      candidates = await ref.read(academyProfileApiProvider).listTrainerCandidates();
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
      return;
    }
    final freshProfile = ref.read(academyProfileProvider).valueOrNull ?? widget.profile;
    final featuredIds = freshProfile.featuredTrainers.map((t) => t.trainerMembershipId).toSet();
    final available = candidates.where((c) => !featuredIds.contains(c.membershipId)).toList();
    if (!mounted) return;
    if (available.isEmpty) {
      AppNotice.error(context, 'Every Trainer/Admin is already featured.');
      return;
    }
    final picked = await showAppOptionSheet<TrainerCandidate>(
      context: context,
      title: 'Add a featured trainer',
      options: available,
      labelOf: (c) => c.fullName,
      optionBuilder: (context, c) => Row(
        children: [
          PersonAvatar(name: c.fullName, seed: c.membershipId, size: 36),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(c.fullName, style: TextStyle(fontSize: AppType.x3l, fontWeight: AppType.medium, color: context.palette.text))),
        ],
      ),
    );
    if (picked == null) return;
    try {
      await ref.read(academyProfileApiProvider).addFeaturedTrainer(picked.membershipId);
      ref.invalidate(academyProfileProvider);
      if (mounted) AppNotice.success(context, '${picked.fullName} added.');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    }
  }

  Future<void> _removeFeaturedTrainer(FeaturedTrainer trainer) async {
    try {
      await ref.read(academyProfileApiProvider).deleteFeaturedTrainer(trainer.id);
      ref.invalidate(academyProfileProvider);
      if (mounted) AppNotice.success(context, 'Removed.');
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    }
  }

  Future<void> _saveDesignation(FeaturedTrainer trainer, String value) async {
    try {
      await ref.read(academyProfileApiProvider).updateFeaturedTrainerDesignation(trainer.id, value.trim().isEmpty ? null : value.trim());
      ref.invalidate(academyProfileProvider);
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final freshProfile = ref.watch(academyProfileProvider).valueOrNull ?? widget.profile;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.page, AppSpacing.page, AppSpacing.page + AppSpacing.listBottom),
        children: [
          _CoverLogoEditor(
            name: freshProfile.name,
            logoUrl: freshProfile.logoUrl,
            coverUrl: freshProfile.coverImageUrl,
            logoBytes: _logoBytes,
            coverBytes: _coverBytes,
            hasPendingLogo: _logoBytes != null,
            hasPendingCover: _coverBytes != null,
            onPickLogo: _pickLogo,
            onPickCover: _pickCover,
            onCancelLogo: _cancelPendingLogo,
            onCancelCover: _cancelPendingCover,
          ),
          const SizedBox(height: AppSpacing.x5l),
          Text('INSTITUTE NAME', style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
            decoration: BoxDecoration(color: palette.surfaceHigh, border: Border.all(color: palette.borderSoft), borderRadius: AppRadii.all(AppRadii.xl)),
            child: Row(children: [
              Expanded(child: Text(freshProfile.name, style: TextStyle(fontSize: AppType.x3l, fontWeight: AppType.bold, color: palette.text))),
              Icon(Icons.lock_outline, size: 14, color: palette.textFaint),
            ]),
          ),
          const SizedBox(height: AppSpacing.xl),
          _EditField(label: 'Tagline', controller: _taglineController, onChanged: (v) => widget.draft.tagline = v),
          const SizedBox(height: AppSpacing.xl),
          _EditField(
            label: 'About the institute',
            controller: _descriptionController,
            onChanged: (v) => widget.draft.description = v,
            maxLines: 5,
          ),
          const SizedBox(height: AppSpacing.md),
          Pressable(
            onTap: () => setState(() => _moreDetailsOpen = !_moreDetailsOpen),
            child: Row(children: [
              Icon(_moreDetailsOpen ? Icons.expand_less : Icons.expand_more, size: 16, color: palette.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Text('More details (established by, owner, additional info)', style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.textMuted)),
            ]),
          ),
          if (_moreDetailsOpen) ...[
            const SizedBox(height: AppSpacing.md),
            _EditField(label: 'Established by', controller: _establishedByController, onChanged: (v) => widget.draft.establishedBy = v),
            const SizedBox(height: AppSpacing.md),
            _EditField(label: 'Owner', controller: _ownerController, onChanged: (v) => widget.draft.ownerName = v),
            const SizedBox(height: AppSpacing.md),
            _EditField(label: 'Additional info', controller: _additionalInfoController, onChanged: (v) => widget.draft.additionalInfo = v, maxLines: 3),
          ],
          const SizedBox(height: AppSpacing.x5l),
          Text('LOCATION', style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          _EditField(label: 'Address', controller: _addressController, onChanged: (v) => widget.draft.address = v, maxLines: 2, showLabel: false, hint: 'Address line, area, etc.'),
          if (freshProfile.city != null || freshProfile.state != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              [freshProfile.city, freshProfile.state].where((s) => s != null && s.isNotEmpty).join(', '),
              style: TextStyle(fontSize: AppType.base, color: palette.textFaint),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _SocialToggleRow(socialKey: 'maps', draft: widget.draft, disabledSocialKeys: widget.disabledSocialKeys),
          const SizedBox(height: AppSpacing.x5l),
          Text('CONTACT DETAILS', style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          _EditField(
            label: 'Phone number',
            controller: _contactController,
            showLabel: false,
            icon: Icons.call_outlined,
            onChanged: (v) {
              widget.draft.contactNumber = v;
              if (_sameAsPhone) {
                widget.draft.whatsapp = v;
                _whatsappController.text = v;
              }
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _EditField(label: 'Email address', controller: _emailController, showLabel: false, icon: Icons.mail_outline, onChanged: (v) => widget.draft.email = v),
          const SizedBox(height: AppSpacing.md),
          _EditField(
            label: 'WhatsApp number',
            controller: _whatsappController,
            showLabel: false,
            icon: Icons.chat_outlined,
            enabled: !_sameAsPhone,
            onChanged: (v) => widget.draft.whatsapp = v,
          ),
          const SizedBox(height: AppSpacing.sm),
          Pressable(
            onTap: () => setState(() {
              _sameAsPhone = !_sameAsPhone;
              if (_sameAsPhone) {
                widget.draft.whatsapp = widget.draft.contactNumber;
                _whatsappController.text = widget.draft.contactNumber;
              }
            }),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppCheckbox(checked: _sameAsPhone, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text('WhatsApp same as phone', style: TextStyle(fontSize: AppType.base, fontWeight: AppType.medium, color: palette.textMuted)),
            ]),
          ),
          const SizedBox(height: AppSpacing.x5l),
          Text('SOCIAL LINKS', style: AppType.sectionLabel(palette.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          Column(children: [
            for (final key in const ['instagram', 'x', 'facebook', 'youtube', 'website']) ...[
              _SocialToggleRow(socialKey: key, draft: widget.draft, disabledSocialKeys: widget.disabledSocialKeys),
              const SizedBox(height: AppSpacing.md),
            ],
          ]),
          const SizedBox(height: AppSpacing.x4l),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('FEATURED TRAINERS', style: AppType.sectionLabel(palette.textMuted)),
              Pressable(
                onTap: _addFeaturedTrainer,
                child: Row(children: [
                  Icon(Icons.add, size: 14, color: palette.primary),
                  const SizedBox(width: AppSpacing.xxs),
                  Text('Add trainer', style: TextStyle(fontSize: AppType.base, fontWeight: AppType.bold, color: palette.primary)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (freshProfile.featuredTrainers.isEmpty)
            Text('No trainers featured yet — add a few faces to the profile.', style: TextStyle(fontSize: AppType.base, color: palette.textFaint))
          else
            Column(
              children: freshProfile.featuredTrainers
                  .map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _FeaturedTrainerEditRow(
                          trainer: t,
                          onDesignationSubmitted: (v) => _saveDesignation(t, v),
                          onRemove: () => _removeFeaturedTrainer(t),
                          onView: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => TrainerCardScreen(membershipId: t.trainerMembershipId, designation: t.designation))),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: AppPrimaryButton(label: 'Done — view profile', icon: Icons.visibility_outlined, onPressed: () => Navigator.of(context).pop()),
        ),
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.maxLines = 1,
    this.showLabel = true,
    this.icon,
    this.hint,
    this.enabled = true,
  });
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final bool showLabel;
  final IconData? icon;
  final String? hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          Text(label.toUpperCase(), style: TextStyle(fontSize: AppType.xs, fontWeight: AppType.bold, color: palette.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: AppSpacing.sm),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: enabled ? palette.surfaceRaised : palette.surfaceHigh,
            border: Border.all(color: palette.border),
            borderRadius: AppRadii.all(AppRadii.xl),
          ),
          child: Row(
            crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 15, color: palette.primary)),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  maxLines: maxLines,
                  enabled: enabled,
                  decoration: InputDecoration(border: InputBorder.none, isDense: true, hintText: hint ?? label),
                  style: TextStyle(fontSize: AppType.x3l, fontWeight: AppType.medium, color: enabled ? palette.text : palette.textFaint),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoverLogoEditor extends StatelessWidget {
  const _CoverLogoEditor({
    required this.name,
    required this.logoUrl,
    required this.coverUrl,
    required this.logoBytes,
    required this.coverBytes,
    required this.hasPendingLogo,
    required this.hasPendingCover,
    required this.onPickLogo,
    required this.onPickCover,
    required this.onCancelLogo,
    required this.onCancelCover,
  });
  final String name;
  final String? logoUrl;
  final String? coverUrl;
  final Uint8List? logoBytes;
  final Uint8List? coverBytes;
  final bool hasPendingLogo;
  final bool hasPendingCover;
  final VoidCallback onPickLogo;
  final VoidCallback onPickCover;
  final VoidCallback onCancelLogo;
  final VoidCallback onCancelCover;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const coverHeight = 128.0;
    const logoSize = 64.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: AppRadii.all(AppRadii.xxl),
              child: Container(
                height: coverHeight,
                decoration: BoxDecoration(
                  gradient: (coverBytes == null && coverUrl == null)
                      ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [palette.primary.withValues(alpha: 0.22), palette.bg])
                      : null,
                ),
                child: coverBytes != null
                    ? Image.memory(coverBytes!, fit: BoxFit.cover, width: double.infinity, height: coverHeight)
                    : coverUrl != null
                        ? Image.network(ApiConfig.resolveMediaUrl(coverUrl)!, fit: BoxFit.cover, width: double.infinity, height: coverHeight)
                        : null,
              ),
            ),
            Positioned(
              top: AppSpacing.md,
              right: AppSpacing.md,
              child: Pressable(
                onTap: onPickCover,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(color: const Color(0x8C0A0F1C), borderRadius: AppRadii.all(AppRadii.lg)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.add_photo_alternate_outlined, size: 14, color: Colors.white),
                    const SizedBox(width: AppSpacing.xs),
                    Text('Change cover', style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: Colors.white)),
                  ]),
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.page,
              top: coverHeight - logoSize / 2,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _LogoMark(name: name, imageUrl: logoUrl, pendingBytes: logoBytes, size: logoSize),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Pressable(
                      onTap: onPickLogo,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(color: palette.surfaceHigh, shape: BoxShape.circle, border: Border.all(color: palette.bg, width: 2)),
                        child: Icon(Icons.edit, size: 11, color: palette.text),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: logoSize / 2 + AppSpacing.md),
        if (hasPendingCover || hasPendingLogo)
          Wrap(
            spacing: AppSpacing.lg,
            children: [
              if (hasPendingCover)
                Pressable(
                  onTap: onCancelCover,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.undo, size: 13, color: palette.notPaid),
                    const SizedBox(width: AppSpacing.xxs),
                    Text('Cancel new cover', style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: palette.notPaid)),
                  ]),
                ),
              if (hasPendingLogo)
                Pressable(
                  onTap: onCancelLogo,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.undo, size: 13, color: palette.notPaid),
                    const SizedBox(width: AppSpacing.xxs),
                    Text('Cancel new logo', style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: palette.notPaid)),
                  ]),
                ),
            ],
          ),
      ],
    );
  }
}

class _FeaturedTrainerEditRow extends StatefulWidget {
  const _FeaturedTrainerEditRow({required this.trainer, required this.onDesignationSubmitted, required this.onRemove, required this.onView});
  final FeaturedTrainer trainer;
  final ValueChanged<String> onDesignationSubmitted;
  final VoidCallback onRemove;
  final VoidCallback onView;

  @override
  State<_FeaturedTrainerEditRow> createState() => _FeaturedTrainerEditRowState();
}

class _FeaturedTrainerEditRowState extends State<_FeaturedTrainerEditRow> {
  late final _controller = TextEditingController(text: widget.trainer.designation ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: palette.surfaceRaised, border: Border.all(color: palette.borderSoft), borderRadius: AppRadii.all(AppRadii.xxl)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pressable(onTap: widget.onView, child: PersonAvatar(name: widget.trainer.fullName, seed: widget.trainer.trainerMembershipId, size: 38)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pressable(
                  onTap: widget.onView,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.trainer.fullName, style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.text)),
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(Icons.chevron_right, size: 14, color: palette.textFaint),
                  ]),
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(color: palette.surfaceHigh, border: Border.all(color: palette.border), borderRadius: AppRadii.all(9)),
                  child: TextField(
                    controller: _controller,
                    onSubmitted: widget.onDesignationSubmitted,
                    onTapOutside: (_) => widget.onDesignationSubmitted(_controller.text),
                    decoration: InputDecoration(border: InputBorder.none, isDense: true, hintText: 'e.g. Head of Dance & Founder', hintStyle: TextStyle(color: palette.textFaint)),
                    style: TextStyle(fontSize: AppType.base, fontWeight: AppType.medium, color: palette.textMuted),
                  ),
                ),
              ],
            ),
          ),
          Pressable(
            onTap: widget.onRemove,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(border: Border.all(color: palette.border), borderRadius: AppRadii.all(AppRadii.sm)),
              child: Icon(Icons.close, size: 13, color: palette.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}
