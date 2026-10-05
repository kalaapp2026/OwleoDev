import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/network/api_config.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';
import 'package:nest_fe/features/academy/data/academy_profile_api.dart';
import 'package:url_launcher/url_launcher.dart';

final academyProfileApiProvider = Provider((ref) => AcademyProfileApi(ref.watch(dioClientProvider)));

final academyProfileProvider = FutureProvider.autoDispose<AcademyProfile>((ref) {
  ref.watch(activeMembershipIdProvider);
  return ref.watch(academyProfileApiProvider).getProfile();
});

const taglineLimit = 60;
const aboutLimit = 400;

// ---------------------------------------------------------------------------------------------
// Cover + logo presets - the look used whenever no photo is uploaded. Stored as keys so the
// server never holds a colour value.
// ---------------------------------------------------------------------------------------------

class CoverPreset {
  const CoverPreset(this.key, this.label, this.colors);
  final String key;
  final String label;
  final List<Color> colors;

  LinearGradient get gradient =>
      LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors, stops: const [0, 0.45, 1]);
}

/// Banner gradients. Fixed colours rather than palette tokens on purpose: a cover reads like a
/// photo, so it looks the same in light and dark mode.
const coverPresets = [
  CoverPreset('teal', 'Teal Stage', [Color(0xFF0F3D37), Color(0xFF14544A), Color(0xFF1B8F7C)]),
  CoverPreset('gold', 'Gold Curtain', [Color(0xFF3A2C0B), Color(0xFF6B4F14), Color(0xFFB8791A)]),
  CoverPreset('violet', 'Violet Velvet', [Color(0xFF241C3D), Color(0xFF3C2E63), Color(0xFF7D63C9)]),
  CoverPreset('coral', 'Coral Spotlight', [Color(0xFF3A2013), Color(0xFF6B3620), Color(0xFFCC6440)]),
  CoverPreset('magenta', 'Magenta Drape', [Color(0xFF351327), Color(0xFF5E1F45), Color(0xFFC24A82)]),
  CoverPreset('navy', 'Midnight Navy', [Color(0xFF0A0F1C), Color(0xFF141E33), Color(0xFF24365C)]),
];

CoverPreset coverPresetFor(String? key) => coverPresets.firstWhere((c) => c.key == key, orElse: () => coverPresets.first);

const logoColorKeys = ['gold', 'primary', 'violet', 'coral', 'magenta', 'gateway'];

/// Gold when unset - what the Dashboard header's tile has always shown.
Color logoColorFor(String? key, AppPalette p) => switch (key) {
      'primary' => p.primary,
      'violet' => p.violet,
      'coral' => p.coral,
      'magenta' => p.magenta,
      'gateway' => p.gateway,
      _ => p.gold,
    };

String academyInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final first = words.isNotEmpty ? words[0][0] : '';
  final second = words.length > 1 ? words[1][0] : '';
  final initials = (first + second).toUpperCase();
  return initials.isEmpty ? 'A' : initials;
}

/// The academy's logo tile: a pending upload, else the stored photo, else coloured initials.
class AcademyLogoMark extends StatelessWidget {
  const AcademyLogoMark({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.colorKey,
    this.pendingBytes,
    this.size = 68,
    this.borderColor,
  });

  final String name;
  final String? imageUrl;
  final String? colorKey;
  final Uint8List? pendingBytes;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resolved = ApiConfig.resolveMediaUrl(imageUrl);
    final Widget content;
    if (pendingBytes != null) {
      content = Image.memory(pendingBytes!, fit: BoxFit.cover);
    } else if (resolved != null) {
      content = Image.network(resolved, fit: BoxFit.cover);
    } else {
      content = Container(
        color: logoColorFor(colorKey, palette),
        alignment: Alignment.center,
        child: Text(
          academyInitials(name),
          style: TextStyle(fontSize: size * 0.33, fontWeight: AppType.heavy, color: const Color(0xFF0A0F1C)),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: AppRadii.all(size * 0.27),
        border: Border.all(color: borderColor ?? palette.bg, width: 3),
        boxShadow: AppShadows.dialog,
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

/// The cover banner: a pending upload, else the stored photo, else the preset gradient.
class AcademyCover extends StatelessWidget {
  const AcademyCover({super.key, required this.imageUrl, required this.styleKey, this.pendingBytes, required this.height});

  final String? imageUrl;
  final String? styleKey;
  final Uint8List? pendingBytes;
  final double height;

  @override
  Widget build(BuildContext context) {
    final resolved = ApiConfig.resolveMediaUrl(imageUrl);
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.palette.surfaceHigh,
        gradient: pendingBytes == null && resolved == null ? coverPresetFor(styleKey).gradient : null,
      ),
      child: pendingBytes != null
          ? Image.memory(pendingBytes!, fit: BoxFit.cover)
          : resolved != null
              ? Image.network(resolved, fit: BoxFit.cover)
              : null,
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Links
// ---------------------------------------------------------------------------------------------

class SocialMeta {
  const SocialMeta({required this.label, required this.icon, required this.colorOf, required this.hint});
  final String label;
  final IconData icon;
  final Color Function(AppPalette) colorOf;
  final String hint;
}

/// Every hideable link. Maps is edited under Location but behaves the same way.
final socialMeta = <String, SocialMeta>{
  'instagram': SocialMeta(label: 'Instagram', icon: Icons.camera_alt_outlined, colorOf: (p) => p.magenta, hint: 'instagram.com/yourpage'),
  'facebook': SocialMeta(label: 'Facebook', icon: Icons.facebook_outlined, colorOf: (p) => p.gateway, hint: 'facebook.com/yourpage'),
  'youtube': SocialMeta(label: 'YouTube', icon: Icons.smart_display_outlined, colorOf: (p) => p.notPaid, hint: 'youtube.com/@yourchannel'),
  'website': SocialMeta(label: 'Website', icon: Icons.language_outlined, colorOf: (p) => p.primary, hint: 'www.youracademy.com'),
  'x': SocialMeta(label: 'X (Twitter)', icon: Icons.alternate_email, colorOf: (p) => p.violet, hint: 'x.com/yourpage'),
  'maps': SocialMeta(label: 'Google Location', icon: Icons.map_outlined, colorOf: (p) => p.gold, hint: 'maps.app.goo.gl/...'),
};

const socialLinkKeys = ['instagram', 'facebook', 'youtube', 'website', 'x'];

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// A bare 10-digit number is an Indian mobile; anything longer already carries a country code.
Uri telUri(String phone) {
  final d = _digits(phone);
  return Uri(scheme: 'tel', path: d.length == 10 ? '+91$d' : '+$d');
}

Uri whatsappUri(String phone) {
  final d = _digits(phone);
  return Uri.parse('https://wa.me/${d.length == 10 ? '91$d' : d}');
}

Uri webUri(String url) {
  final trimmed = url.trim();
  return Uri.parse(RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed) ? trimmed : 'https://$trimmed');
}

Future<void> openUri(BuildContext context, Uri uri) async {
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) AppNotice.error(context, 'Could not open this link.');
  }
}

// ---------------------------------------------------------------------------------------------
// Draft
// ---------------------------------------------------------------------------------------------

class DraftTrainer {
  DraftTrainer({required this.membershipId, required this.fullName, this.imageUrl, this.designation = '', this.courseNames = const []});
  final String membershipId;
  final String fullName;
  final String? imageUrl;
  String designation;

  /// Only known for trainers added in this editing session (from the picker); used as the
  /// designation field's hint.
  final List<String> courseNames;
}

/// Every editable part of the profile, held locally until Publish. The view screen always renders
/// this, so "view" and "preview" are the same screen. Highlights and branches are the exception:
/// they keep their own immediate add/remove.
class ProfileDraft {
  ProfileDraft.from(AcademyProfile p)
      : name = p.name,
        tagline = p.tagline ?? '',
        description = p.description ?? '',
        establishedBy = p.establishedBy ?? '',
        ownerName = p.ownerName ?? '',
        additionalInfo = p.additionalInfo ?? '',
        address = p.address ?? '',
        area = p.area ?? '',
        city = p.city ?? '',
        state = p.state ?? '',
        pinCode = p.pinCode ?? '',
        contactNumber = p.contactNumber ?? '',
        email = p.email ?? '',
        whatsapp = p.whatsapp ?? '',
        links = {
          'instagram': p.instagramUrl ?? '',
          'facebook': p.facebookUrl ?? '',
          'youtube': p.youtubeUrl ?? '',
          'website': p.websiteUrl ?? '',
          'x': p.xUrl ?? '',
          'maps': p.mapsUrl ?? '',
        },
        hiddenLinks = {...p.hiddenLinks},
        coverStyle = coverPresetFor(p.coverStyle).key,
        logoColor = p.logoColor ?? logoColorKeys.first,
        logoUrl = p.logoUrl,
        coverUrl = p.coverImageUrl,
        featured = p.featuredTrainers
            .map((t) => DraftTrainer(
                membershipId: t.trainerMembershipId, fullName: t.fullName, imageUrl: t.profileImageUrl, designation: t.designation ?? ''))
            .toList();

  String name;
  String tagline;
  String description;
  String establishedBy;
  String ownerName;
  String additionalInfo;
  String address;
  String area;
  String city;
  String state;
  String pinCode;
  String contactNumber;
  String email;
  String whatsapp;
  final Map<String, String> links;
  final Set<String> hiddenLinks;
  String coverStyle;
  String logoColor;
  final List<DraftTrainer> featured;

  /// The published photo URLs; set to null to remove the photo on Publish.
  String? logoUrl;
  String? coverUrl;

  Uint8List? newLogoBytes;
  String? newLogoName;
  Uint8List? newCoverBytes;
  String? newCoverName;

  bool linkVisible(String key) => !hiddenLinks.contains(key) && (links[key] ?? '').trim().isNotEmpty;

  String get fullAddress =>
      [address, area, city, '$state ${pinCode.trim()}'].map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');

  /// The PUT /academies/me body. Also the basis of [isDirtyAgainst].
  Map<String, dynamic> toBody({required AcademyProfile published}) {
    String? orNull(String s) => s.trim().isEmpty ? null : s.trim();
    return {
      'name': name.trim(),
      'tagline': orNull(tagline),
      'description': orNull(description),
      'establishedBy': orNull(establishedBy),
      'ownerName': orNull(ownerName),
      'additionalInfo': orNull(additionalInfo),
      'address': address.trim(),
      'area': area.trim(),
      'city': city.trim(),
      'state': state.trim(),
      'pinCode': pinCode.trim(),
      'contactNumber': contactNumber.trim(),
      'email': orNull(email),
      'whatsapp': orNull(whatsapp),
      'instagramUrl': orNull(links['instagram']!),
      'facebookUrl': orNull(links['facebook']!),
      'youtubeUrl': orNull(links['youtube']!),
      'websiteUrl': orNull(links['website']!),
      'xUrl': orNull(links['x']!),
      'mapsUrl': orNull(links['maps']!),
      'coverStyle': coverStyle,
      'logoColor': logoColor,
      'hiddenLinks': (hiddenLinks.toList()..sort()),
      'removeLogo': newLogoBytes == null && logoUrl == null && published.logoUrl != null,
      'removeCover': newCoverBytes == null && coverUrl == null && published.coverImageUrl != null,
      'featuredTrainers': [
        for (final t in featured) {'trainerMembershipId': t.membershipId, 'designation': orNull(t.designation)},
      ],
    };
  }

  bool isDirtyAgainst(AcademyProfile published) =>
      newLogoBytes != null ||
      newCoverBytes != null ||
      jsonEncode(toBody(published: published)) != jsonEncode(ProfileDraft.from(published).toBody(published: published));

  /// The first thing blocking Publish, or null.
  String? validationError() {
    if (name.trim().isEmpty) return 'Give the institute a name.';
    if (address.trim().isEmpty) return 'Add an address line under Location.';
    if (city.trim().isEmpty) return 'Add a city under Location.';
    if (state.trim().isEmpty) return 'Choose a state under Location.';
    if (pinCode.trim().isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(pinCode.trim())) return 'A pin code is 6 digits.';
    if (_digits(contactNumber).length < 10) return 'Add a phone number with at least 10 digits.';
    if (email.trim().isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) return 'That email address looks incomplete.';
    return null;
  }
}

const indianStates = [
  'Andaman and Nicobar Islands', 'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chandigarh',
  'Chhattisgarh', 'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Goa', 'Gujarat', 'Haryana',
  'Himachal Pradesh', 'Jammu and Kashmir', 'Jharkhand', 'Karnataka', 'Kerala', 'Ladakh', 'Lakshadweep',
  'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Puducherry',
  'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
  'West Bengal',
];
/// A tappable contact row: icon chip, caption + value, trailing chevron. Opens the dialer, mail
/// app or WhatsApp. Shared with the trainer profile screen.
class ContactLinkRow extends StatelessWidget {
  const ContactLinkRow({super.key, required this.icon, required this.caption, required this.value, required this.uri, this.color});
  final IconData icon;
  final String caption;
  final String value;
  final Uri uri;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = color ?? palette.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Pressable(
        onTap: () => openUri(context, uri),
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
                    const SizedBox(height: 1),
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
