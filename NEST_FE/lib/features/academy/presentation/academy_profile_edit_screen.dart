import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/avatar.dart';
import 'package:nest_fe/core/design/buttons.dart';
import 'package:nest_fe/core/design/confirm_dialog.dart';
import 'package:nest_fe/core/design/people_picker_sheet.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/design/sheets.dart';
import 'package:nest_fe/core/error/api_exception.dart';
import 'package:nest_fe/core/widgets/app_notice.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';
import 'package:nest_fe/features/academy/presentation/academy_profile_shared.dart';
import 'package:nest_fe/features/academy/presentation/trainer_card_screen.dart';

/// The only editing surface for the academy profile. Every change mutates [draft] in place (the
/// same object the view screen holds) and calls [onChanged]; nothing reaches the server until the
/// view screen's Publish.
class AcademyProfileEditScreen extends ConsumerStatefulWidget {
  const AcademyProfileEditScreen({
    super.key,
    required this.published,
    required this.draft,
    required this.onChanged,
    required this.onDiscard,
  });

  final AcademyProfile published;
  final ProfileDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onDiscard;

  @override
  ConsumerState<AcademyProfileEditScreen> createState() => _AcademyProfileEditScreenState();
}

enum _ImagePanel { cover, logo }

class _AcademyProfileEditScreenState extends ConsumerState<AcademyProfileEditScreen> {
  ProfileDraft get d => widget.draft;

  _ImagePanel? _panel;
  late bool _sameAsPhone = d.whatsapp.isNotEmpty && d.whatsapp == d.contactNumber;
  late bool _moreOpen = d.establishedBy.isNotEmpty || d.ownerName.isNotEmpty || d.additionalInfo.isNotEmpty;
  List<TrainerCandidate>? _candidates;

  late final _name = TextEditingController(text: d.name);
  late final _tagline = TextEditingController(text: d.tagline);
  late final _about = TextEditingController(text: d.description);
  late final _establishedBy = TextEditingController(text: d.establishedBy);
  late final _owner = TextEditingController(text: d.ownerName);
  late final _additionalInfo = TextEditingController(text: d.additionalInfo);
  late final _address = TextEditingController(text: d.address);
  late final _area = TextEditingController(text: d.area);
  late final _city = TextEditingController(text: d.city);
  late final _pin = TextEditingController(text: d.pinCode);
  late final _phone = TextEditingController(text: d.contactNumber);
  late final _email = TextEditingController(text: d.email);
  late final _whatsapp = TextEditingController(text: d.whatsapp);

  @override
  void dispose() {
    for (final c in [_name, _tagline, _about, _establishedBy, _owner, _additionalInfo, _address, _area, _city, _pin, _phone, _email, _whatsapp]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed(VoidCallback mutate) {
    setState(mutate);
    widget.onChanged();
  }

  Future<void> _discard() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Discard draft changes?',
      message: "Your edits will be reverted back to the last published version of the profile. This can't be undone.",
      confirmLabel: 'Discard',
    );
    if (!confirmed || !mounted) return;
    widget.onDiscard();
    Navigator.of(context).pop();
  }

  Future<void> _pickImage(_ImagePanel which) async {
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (!mounted || result == null || result.files.isEmpty || result.files.first.bytes == null) return;
    final f = result.files.first;
    _changed(() {
      if (which == _ImagePanel.cover) {
        d.newCoverBytes = f.bytes;
        d.newCoverName = f.name;
      } else {
        d.newLogoBytes = f.bytes;
        d.newLogoName = f.name;
      }
      _panel = null;
    });
  }

  void _removeImage(_ImagePanel which) => _changed(() {
        if (which == _ImagePanel.cover) {
          d.coverUrl = null;
          d.newCoverBytes = null;
        } else {
          d.logoUrl = null;
          d.newLogoBytes = null;
        }
        _panel = null;
      });

  Future<void> _pickTrainers() async {
    try {
      _candidates ??= await ref.read(academyProfileApiProvider).listTrainerCandidates();
    } on ApiException catch (e) {
      if (mounted) AppNotice.error(context, e.message);
      return;
    }
    if (!mounted) return;
    final candidates = _candidates!;
    final picked = await showPeoplePickerSheet(
      context: context,
      title: 'Featured trainers',
      searchHint: 'Search trainers',
      emptyLabel: 'No trainers registered yet.',
      accentColor: context.palette.gold,
      people: [
        for (final c in candidates)
          PickablePerson(id: c.membershipId, name: c.fullName, subtitle: c.courseNames.isEmpty ? null : c.courseNames.join(', ')),
      ],
      initiallySelected: d.featured.map((t) => t.membershipId).toSet(),
    );
    if (picked == null) return;
    _changed(() {
      d.featured.removeWhere((t) => !picked.contains(t.membershipId));
      final already = d.featured.map((t) => t.membershipId).toSet();
      for (final c in candidates.where((c) => picked.contains(c.membershipId) && !already.contains(c.membershipId))) {
        d.featured.add(DraftTrainer(membershipId: c.membershipId, fullName: c.fullName, imageUrl: c.profileImageUrl, courseNames: c.courseNames));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDirty = d.isDirtyAgainst(widget.published);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(
              title: 'Edit Profile',
              subtitle: 'Changes stay in draft until published',
              actions: [
                if (isDirty)
                  Pressable(
                    onTap: _discard,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs, vertical: AppSpacing.xs),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.restore, size: 14, color: palette.textMuted),
                        const SizedBox(width: AppSpacing.xxs),
                        Text('Discard', style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.bold, color: palette.textMuted)),
                      ]),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.page),
                children: [
                  _coverLogoEditor(palette),
                  const SizedBox(height: AppSpacing.x3l),
                  _Field(label: 'Institute name', controller: _name, hint: 'e.g. Owleo Performing Arts Academy', onChanged: (v) => _changed(() => d.name = v)),
                  const SizedBox(height: AppSpacing.x3l),
                  _Field(
                    label: 'Tagline',
                    controller: _tagline,
                    hint: 'A short line under your name',
                    maxLength: taglineLimit,
                    onChanged: (v) => _changed(() => d.tagline = v),
                  ),
                  const SizedBox(height: AppSpacing.x3l),
                  _Field(
                    label: 'About the institute',
                    controller: _about,
                    hint: 'Tell prospective students and parents about your academy',
                    maxLength: aboutLimit,
                    maxLines: 5,
                    onChanged: (v) => _changed(() => d.description = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _moreDetails(palette),
                  const SizedBox(height: AppSpacing.x3l),
                  _Note(text: "Active students, trainers and course counts are pulled automatically from your records and can't be edited here."),
                  const SizedBox(height: AppSpacing.x3l),
                  _Label('Location'),
                  _Box(controller: _address, hint: 'Address line', onChanged: (v) => _changed(() => d.address = v)),
                  const SizedBox(height: AppSpacing.sm),
                  Row(children: [
                    Expanded(child: _Box(controller: _area, hint: 'Area', onChanged: (v) => _changed(() => d.area = v))),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _Box(controller: _city, hint: 'City', onChanged: (v) => _changed(() => d.city = v))),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  Row(children: [
                    Expanded(
                      child: AttachedSelect<String>(
                        label: 'State',
                        showLabel: false,
                        placeholder: 'State',
                        options: [if (d.state.isNotEmpty && !indianStates.contains(d.state)) d.state, ...indianStates],
                        labelOf: (s) => s,
                        value: d.state.isEmpty ? null : d.state,
                        searchable: true,
                        searchHint: 'Search states',
                        panelSpan: PanelSpan.left,
                        onSelected: (s) => _changed(() => d.state = s),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _Box(
                        controller: _pin,
                        hint: 'Pin code',
                        keyboardType: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        onChanged: (v) => _changed(() => d.pinCode = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  _LinkToggleRow(linkKey: 'maps', draft: d, onChanged: () => _changed(() {})),
                  const SizedBox(height: AppSpacing.x3l),
                  _Label('Contact details'),
                  _Box(
                    controller: _phone,
                    hint: 'Phone number',
                    icon: Icons.call_outlined,
                    keyboardType: TextInputType.phone,
                    formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                    onChanged: (v) => _changed(() {
                      d.contactNumber = v;
                      if (_sameAsPhone) {
                        d.whatsapp = v;
                        _whatsapp.text = v;
                      }
                    }),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _Box(
                    controller: _email,
                    hint: 'Email address',
                    icon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (v) => _changed(() => d.email = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _Box(
                    controller: _whatsapp,
                    hint: 'WhatsApp number',
                    icon: Icons.chat_outlined,
                    iconColor: palette.paidManual,
                    enabled: !_sameAsPhone,
                    keyboardType: TextInputType.phone,
                    formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                    onChanged: (v) => _changed(() => d.whatsapp = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Pressable(
                    onTap: () => _changed(() {
                      _sameAsPhone = !_sameAsPhone;
                      if (_sameAsPhone) {
                        d.whatsapp = d.contactNumber;
                        _whatsapp.text = d.contactNumber;
                      }
                    }),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AppCheckbox(checked: _sameAsPhone, size: 16),
                      const SizedBox(width: AppSpacing.sm),
                      Text('WhatsApp same as phone', style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.semi, color: palette.textMuted)),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.x3l),
                  _Label('Social links'),
                  for (final key in socialLinkKeys) ...[
                    _LinkToggleRow(linkKey: key, draft: d, onChanged: () => _changed(() {})),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(child: _Label('Featured trainers', bottom: 0)),
                      Pressable(
                        onTap: _pickTrainers,
                        child: Row(children: [
                          Icon(Icons.add, size: 14, color: palette.primary),
                          const SizedBox(width: AppSpacing.xxs),
                          Text('Add trainer', style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.bold, color: palette.primary)),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (d.featured.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: 2),
                      child: Text('No trainers featured yet — add a few faces to the profile.',
                          style: TextStyle(fontSize: AppType.base, color: palette.textFaint)),
                    ),
                  for (final t in d.featured)
                    Padding(
                      key: ValueKey(t.membershipId),
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _FeaturedTrainerEditCard(
                        trainer: t,
                        onDesignationChanged: (v) => _changed(() => t.designation = v),
                        onRemove: () => _changed(() => d.featured.remove(t)),
                        onView: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => TrainerCardScreen(
                                membershipId: t.membershipId, designation: t.designation.trim().isEmpty ? null : t.designation.trim()))),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.x3l),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.borderSoft))),
              child: AppPrimaryButton(label: 'Done — view profile', icon: Icons.visibility_outlined, onPressed: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moreDetails(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Pressable(
          onTap: () => setState(() => _moreOpen = !_moreOpen),
          child: Row(children: [
            Icon(_moreOpen ? Icons.expand_less : Icons.expand_more, size: 16, color: palette.textMuted),
            const SizedBox(width: AppSpacing.xxs),
            Text('More details (founder, owner, additional info)',
                style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.bold, color: palette.textMuted)),
          ]),
        ),
        if (_moreOpen) ...[
          const SizedBox(height: AppSpacing.md),
          _Field(label: 'Established by', controller: _establishedBy, hint: 'Founder', onChanged: (v) => _changed(() => d.establishedBy = v)),
          const SizedBox(height: AppSpacing.md),
          _Field(label: 'Owner', controller: _owner, hint: 'Owner name', onChanged: (v) => _changed(() => d.ownerName = v)),
          const SizedBox(height: AppSpacing.md),
          _Field(
            label: 'Additional info',
            controller: _additionalInfo,
            hint: 'Anything else worth knowing',
            maxLines: 3,
            onChanged: (v) => _changed(() => d.additionalInfo = v),
          ),
        ],
      ],
    );
  }

  /// The cover box and the logo are siblings in an unclipped Stack, so only the cover's own
  /// corners are clipped and the logo overlapping its bottom edge always renders in full.
  Widget _coverLogoEditor(AppPalette palette) {
    const coverHeight = 128.0;
    const logoSize = 64.0;
    const logoTop = coverHeight - 36;
    final hasCoverPhoto = d.newCoverBytes != null || d.coverUrl != null;
    final hasLogoPhoto = d.newLogoBytes != null || d.logoUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: logoTop + logoSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: AppRadii.all(AppRadii.x3l),
                child: AcademyCover(imageUrl: d.coverUrl, styleKey: d.coverStyle, pendingBytes: d.newCoverBytes, height: coverHeight),
              ),
              Positioned(
                top: AppSpacing.md,
                right: AppSpacing.md,
                child: Pressable(
                  onTap: () => setState(() => _panel = _panel == _ImagePanel.cover ? null : _ImagePanel.cover),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0x8C0A0F1C),
                      borderRadius: AppRadii.all(AppRadii.md),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_photo_alternate_outlined, size: 13, color: Colors.white),
                      const SizedBox(width: AppSpacing.xs),
                      Text('Change cover', style: TextStyle(fontSize: AppType.sm, fontWeight: AppType.bold, color: Colors.white)),
                    ]),
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.xxl,
                top: logoTop,
                child: AcademyLogoMark(name: d.name, imageUrl: d.logoUrl, colorKey: d.logoColor, pendingBytes: d.newLogoBytes, size: logoSize),
              ),
              Positioned(
                left: AppSpacing.xxl + logoSize - 22,
                top: logoTop + logoSize - 22,
                child: Pressable(
                  onTap: () => setState(() => _panel = _panel == _ImagePanel.logo ? null : _ImagePanel.logo),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: AppRadii.all(AppRadii.sm), border: Border.all(color: palette.bg, width: 2)),
                    child: Icon(Icons.edit, size: 11, color: palette.text),
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: AppMotion.fade,
          alignment: Alignment.topCenter,
          child: _panel == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: _panel == _ImagePanel.cover
                      ? _ImagePanelCard(
                          uploadLabel: 'Upload cover photo',
                          choiceLabel: 'Or choose a style',
                          onUpload: () => _pickImage(_ImagePanel.cover),
                          onRemove: hasCoverPhoto ? () => _removeImage(_ImagePanel.cover) : null,
                          choices: GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: AppSpacing.sm,
                            crossAxisSpacing: AppSpacing.sm,
                            childAspectRatio: 2.4,
                            children: [
                              for (final c in coverPresets)
                                _Swatch(
                                  selected: !hasCoverPhoto && d.coverStyle == c.key,
                                  gradient: c.gradient,
                                  tooltip: c.label,
                                  onTap: () => _changed(() {
                                    d.coverStyle = c.key;
                                    d.coverUrl = null;
                                    d.newCoverBytes = null;
                                    _panel = null;
                                  }),
                                ),
                            ],
                          ),
                        )
                      : _ImagePanelCard(
                          uploadLabel: 'Upload logo image',
                          choiceLabel: 'Or choose a mark colour',
                          onUpload: () => _pickImage(_ImagePanel.logo),
                          onRemove: hasLogoPhoto ? () => _removeImage(_ImagePanel.logo) : null,
                          choices: Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.md,
                            children: [
                              for (final key in logoColorKeys)
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: _Swatch(
                                    selected: !hasLogoPhoto && d.logoColor == key,
                                    color: logoColorFor(key, palette),
                                    onTap: () => _changed(() {
                                      d.logoColor = key;
                                      d.logoUrl = null;
                                      d.newLogoBytes = null;
                                      _panel = null;
                                    }),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}

class _ImagePanelCard extends StatelessWidget {
  const _ImagePanelCard({required this.uploadLabel, required this.choiceLabel, required this.onUpload, required this.choices, this.onRemove});
  final String uploadLabel;
  final String choiceLabel;
  final VoidCallback onUpload;
  final Widget choices;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: palette.surfaceRaised, border: Border.all(color: palette.border), borderRadius: AppRadii.all(AppRadii.xl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: onUpload,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              decoration: BoxDecoration(color: palette.surfaceHigh, border: Border.all(color: palette.border), borderRadius: AppRadii.all(AppRadii.md)),
              child: Row(children: [
                Icon(Icons.upload_outlined, size: 14, color: palette.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(uploadLabel, style: TextStyle(fontSize: AppType.md, fontWeight: AppType.bold, color: palette.text)),
              ]),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(choiceLabel.toUpperCase(),
              style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.bold, color: palette.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: AppSpacing.sm),
          choices,
          if (onRemove != null) ...[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Pressable(
                onTap: onRemove!,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.delete_outline, size: 13, color: palette.notPaid),
                    const SizedBox(width: AppSpacing.xxs),
                    Text('Remove photo', style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.bold, color: palette.notPaid)),
                  ]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.selected, required this.onTap, this.gradient, this.color, this.tooltip});
  final bool selected;
  final VoidCallback onTap;
  final Gradient? gradient;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final swatch = Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: AppRadii.all(AppRadii.md),
          border: Border.all(color: selected ? (gradient != null ? palette.primary : palette.text) : palette.border, width: selected ? 2 : 1),
        ),
        alignment: gradient != null ? Alignment.topRight : Alignment.center,
        padding: const EdgeInsets.all(3),
        child: selected ? Icon(Icons.check, size: 13, color: gradient != null ? Colors.white : const Color(0xFF0A0F1C)) : null,
      ),
    );
    return tooltip == null ? swatch : Tooltip(message: tooltip!, child: swatch);
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.bottom = AppSpacing.sm});
  final String text;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.bold, color: context.palette.textMuted, letterSpacing: 0.5)),
      );
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(color: palette.surfaceRaised, border: Border.all(color: palette.borderSoft), borderRadius: AppRadii.all(AppRadii.xl)),
      child: Row(children: [
        Icon(Icons.auto_awesome_outlined, size: 14, color: palette.textFaint),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: TextStyle(fontSize: AppType.sm, color: palette.textFaint, height: 1.5))),
      ]),
    );
  }
}

/// A labelled input, with an "n/limit" counter beside the label when [maxLength] is set.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller, required this.onChanged, this.hint, this.maxLength, this.maxLines = 1});
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hint;
  final int? maxLength;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _Label(label)),
          if (maxLength != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, value, _) => Text('${value.text.length}/$maxLength',
                    style: TextStyle(fontSize: AppType.tiny, fontWeight: AppType.semi, color: palette.textFaint)),
              ),
            ),
        ]),
        _Box(
          controller: controller,
          hint: hint ?? label,
          maxLines: maxLines,
          formatters: [if (maxLength != null) LengthLimitingTextInputFormatter(maxLength)],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// The prototype's input box - raised surface, 14 radius, optional leading icon.
class _Box extends StatelessWidget {
  const _Box({
    required this.controller,
    required this.onChanged,
    required this.hint,
    this.icon,
    this.iconColor,
    this.maxLines = 1,
    this.enabled = true,
    this.keyboardType,
    this.formatters = const [],
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final IconData? icon;
  final Color? iconColor;
  final int maxLines;
  final bool enabled;
  final TextInputType? keyboardType;
  final List<TextInputFormatter> formatters;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        decoration: BoxDecoration(color: palette.surfaceRaised, border: Border.all(color: palette.border), borderRadius: AppRadii.all(AppRadii.xl)),
        child: Row(
          crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: iconColor ?? palette.primary),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                maxLines: maxLines,
                enabled: enabled,
                keyboardType: maxLines > 1 ? TextInputType.multiline : keyboardType,
                inputFormatters: formatters,
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 3),
                  hintText: hint,
                  hintStyle: TextStyle(color: palette.textFaint, fontWeight: AppType.medium),
                ),
                style: TextStyle(
                  fontSize: maxLines > 1 ? AppType.lg : AppType.x3l,
                  fontWeight: maxLines > 1 ? AppType.medium : AppType.semi,
                  color: palette.text,
                  height: maxLines > 1 ? 1.5 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small track-and-knob switch, as in the prototype. [FlipToggle] is a labelled pill, not this.
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

/// One on/off + URL row, the same for every social link and Google location. Switching off keeps
/// the URL, so switching back on restores it.
class _LinkToggleRow extends StatefulWidget {
  const _LinkToggleRow({required this.linkKey, required this.draft, required this.onChanged});
  final String linkKey;
  final ProfileDraft draft;
  final VoidCallback onChanged;

  @override
  State<_LinkToggleRow> createState() => _LinkToggleRowState();
}

class _LinkToggleRowState extends State<_LinkToggleRow> {
  late final _controller = TextEditingController(text: widget.draft.links[widget.linkKey]);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = socialMeta[widget.linkKey]!;
    final color = meta.colorOf(palette);
    final enabled = !widget.draft.hiddenLinks.contains(widget.linkKey);

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
                onChanged: (v) {
                  setState(() => v ? widget.draft.hiddenLinks.remove(widget.linkKey) : widget.draft.hiddenLinks.add(widget.linkKey));
                  widget.onChanged();
                },
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 9),
              decoration: BoxDecoration(color: palette.surfaceHigh, border: Border.all(color: palette.border), borderRadius: AppRadii.all(AppRadii.md)),
              child: Row(
                children: [
                  Icon(Icons.link, size: 13, color: palette.textFaint),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      keyboardType: TextInputType.url,
                      onChanged: (v) {
                        widget.draft.links[widget.linkKey] = v;
                        widget.onChanged();
                      },
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: meta.hint,
                        hintStyle: TextStyle(color: palette.textFaint, fontSize: AppType.md),
                      ),
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

class _FeaturedTrainerEditCard extends StatefulWidget {
  const _FeaturedTrainerEditCard({required this.trainer, required this.onDesignationChanged, required this.onRemove, required this.onView});
  final DraftTrainer trainer;
  final ValueChanged<String> onDesignationChanged;
  final VoidCallback onRemove;
  final VoidCallback onView;

  @override
  State<_FeaturedTrainerEditCard> createState() => _FeaturedTrainerEditCardState();
}

class _FeaturedTrainerEditCardState extends State<_FeaturedTrainerEditCard> {
  late final _controller = TextEditingController(text: widget.trainer.designation);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final t = widget.trainer;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: palette.surfaceRaised, border: Border.all(color: palette.borderSoft), borderRadius: AppRadii.all(AppRadii.xl)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pressable(onTap: widget.onView, child: PersonAvatar(name: t.fullName, seed: t.membershipId, size: 38)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pressable(
                  onTap: widget.onView,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(t.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.text)),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(Icons.chevron_right, size: 14, color: palette.textFaint),
                  ]),
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 7),
                  decoration: BoxDecoration(color: palette.surfaceHigh, border: Border.all(color: palette.border), borderRadius: AppRadii.all(9)),
                  child: TextField(
                    controller: _controller,
                    onChanged: widget.onDesignationChanged,
                    inputFormatters: [LengthLimitingTextInputFormatter(120)],
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: t.courseNames.isNotEmpty ? t.courseNames.join(' & ') : 'Designation, e.g. Senior Music Trainer',
                      hintStyle: TextStyle(color: palette.textFaint, fontSize: AppType.smd),
                    ),
                    style: TextStyle(fontSize: AppType.smd, fontWeight: AppType.semi, color: palette.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Pressable(
            onTap: widget.onRemove,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(border: Border.all(color: palette.border), borderRadius: AppRadii.all(AppRadii.sm)),
              child: Icon(Icons.close, size: 12, color: palette.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}
