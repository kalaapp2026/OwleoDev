import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/attached_select.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/format/money.dart';
import 'package:nest_fe/features/enrolment/data/person_details.dart';

/// A labelled slot in a form: small caps label, the control, and an optional hint or error below.
///
/// Errors take the hint's place rather than stacking beneath it - showing both at once makes the
/// row grow and pushes the rest of the form down as you type, and the error is the only line that
/// matters at that moment anyway.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.error,
    this.required = false,
    this.bottomGap = AppSpacing.x4l,
  });

  final String label;
  final Widget child;
  final String? hint;
  final String? error;
  final bool required;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final footer = error ?? hint;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label.toUpperCase(),
                  style: AppType.sectionLabel(palette.textMuted)),
              if (required) ...[
                const SizedBox(width: 3),
                Text('*',
                    style: TextStyle(
                        fontSize: AppType.xs,
                        fontWeight: AppType.bold,
                        color: palette.notPaid)),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(footer,
                style: TextStyle(
                  fontSize: AppType.sm,
                  color: error != null ? palette.notPaid : palette.textFaint,
                  height: 1.4,
                )),
          ],
        ],
      ),
    );
  }
}

/// The shared text input styling. Every form field in this module goes through here so a change
/// to the field shape does not have to be chased across twenty call sites.
InputDecoration appInputDecoration(
  AppPalette palette,
  String hint, {
  Widget? prefix,
  bool hasError = false,
}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: AppRadii.all(AppRadii.xl),
        borderSide: BorderSide(color: color),
      );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(
        fontSize: AppType.lg, fontWeight: AppType.regular, color: palette.textFaint),
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
    filled: true,
    fillColor: palette.surfaceRaised,
    contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
    border: border(palette.border),
    enabledBorder: border(hasError ? palette.notPaid : palette.border),
    focusedBorder: border(palette.primary),
  );
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.icon,
    this.hasError = false,
    this.maxLines = 1,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? icon;
  final bool hasError;
  final int maxLines;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      autofocus: autofocus,
      style: TextStyle(
          fontSize: AppType.xxl, fontWeight: AppType.medium, color: palette.text),
      decoration: appInputDecoration(
        palette,
        hint,
        hasError: hasError,
        prefix: icon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.sm),
                child: Icon(icon, size: 15, color: palette.textFaint),
              ),
      ),
    );
  }
}

/// A phone number split into a dialling-code select and a digits field.
///
/// Kept as one widget because the two halves are one value: the code alone is meaningless, and
/// storing them apart means every reader has to remember to reassemble them.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.code,
    required this.controller,
    required this.onCodeChanged,
    this.onChanged,
    this.hint = 'Phone number',
    this.hasError = false,
  });

  final String code;
  final TextEditingController controller;
  final ValueChanged<String> onCodeChanged;
  final ValueChanged<String>? onChanged;
  final String hint;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selected = CountryCode.options.firstWhere(
      (c) => c.code == code,
      orElse: () => CountryCode.options.first,
    );
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: AttachedSelect<CountryCode>(
            label: 'Code',
            options: CountryCode.options,
            labelOf: (c) => c.code,
            value: selected,
            onSelected: (c) => onCodeChanged(c.code),
            optionBuilder: (context, option, _) => Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Text(option.code,
                      style: TextStyle(
                          fontSize: AppType.xl,
                          fontWeight: AppType.bold,
                          color: option.code == code ? palette.primary : palette.text)),
                ),
                Expanded(
                  child: Text(option.country,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppType.md, color: palette.textMuted)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppTextField(
            controller: controller,
            hint: hint,
            onChanged: onChanged,
            hasError: hasError,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(15),
            ],
          ),
        ),
      ],
    );
  }
}

/// A tappable tile that reads like an input but opens a picker. Used for dates and for any
/// selection that needs a sheet rather than a dropdown.
class PickerTile extends StatelessWidget {
  const PickerTile({
    super.key,
    required this.icon,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.accent,
    this.trailing,
    this.hasError = false,
  });

  final IconData icon;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;
  final Color? accent;
  final String? trailing;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final filled = value != null && value!.isNotEmpty;
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadii.all(AppRadii.xl),
            border: Border.all(color: hasError ? palette.notPaid : palette.border),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 15,
                  color: filled ? (accent ?? palette.primary) : palette.textFaint),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  filled ? value! : placeholder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.xxl,
                    fontWeight: filled ? AppType.bold : AppType.medium,
                    color: filled ? palette.text : palette.textFaint,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(trailing!,
                    style: TextStyle(
                        fontSize: AppType.base,
                        fontWeight: AppType.bold,
                        color: palette.primary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A wrap of single-select pills - gender, blood group, and anywhere else the option set is short
/// enough that a dropdown would hide it for no reason.
class ChoicePills extends StatelessWidget {
  const ChoicePills({
    super.key,
    required this.options,
    required this.value,
    required this.onSelected,
    this.accent,
  });

  final List<String> options;
  final String? value;
  final ValueChanged<String?> onSelected;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = accent ?? palette.primary;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: options.map((option) {
        final selected = option == value;
        return Pressable(
          // Tapping the selected pill clears it: these fields are optional, and without this
          // there is no way back to "not answered" once something has been tapped.
          onTap: () => onSelected(selected ? null : option),
          child: AnimatedContainer(
            duration: AppMotion.press,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x3l, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: selected ? color : palette.surfaceRaised,
              borderRadius: AppRadii.all(AppRadii.pill),
              border: Border.all(color: selected ? color : palette.border),
            ),
            child: Text(
              option,
              style: TextStyle(
                fontSize: AppType.lg,
                fontWeight: selected ? AppType.bold : AppType.medium,
                color: selected ? palette.onPrimary : palette.textMuted,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// A collapsible group of fields. The registration form is long; without this, the parts that are
/// genuinely optional (address, emergency contact) dominate the scroll and make the required ones
/// harder to find.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.expanded,
    required this.onToggle,
    required this.children,
    this.subtitle,
    this.badge,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  /// A short status shown on the collapsed header - "3 courses", "incomplete".
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadii.all(AppRadii.xxl),
        border: Border.all(color: palette.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                children: [
                  Container(
                    height: 30,
                    width: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: AppRadii.all(AppRadii.md),
                    ),
                    child: Icon(icon, size: 15, color: accent),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            style: TextStyle(
                                fontSize: AppType.x3l,
                                fontWeight: AppType.bold,
                                color: palette.text)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!,
                              style: TextStyle(
                                  fontSize: AppType.sm, color: palette.textMuted)),
                        ],
                      ],
                    ),
                  ),
                  if (badge != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: AppRadii.all(AppRadii.pill),
                      ),
                      child: Text(badge!,
                          style: TextStyle(
                              fontSize: AppType.tiny,
                              fontWeight: AppType.heavy,
                              letterSpacing: 0.3,
                              color: accent)),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: AppMotion.chevron,
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.collapse,
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Formats a date for the picker tiles. Thin wrapper so the form does not import the money module
/// just for one function.
String? formatOptionalDate(DateTime? date) =>
    date == null ? null : formatFeeDate(date);
