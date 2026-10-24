import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/design/country_picker_sheet.dart';
import 'package:nest_fe/core/design/pressable.dart';
import 'package:nest_fe/core/validation/countries.dart';
import 'package:nest_fe/core/validation/input_formats.dart';
import 'package:nest_fe/core/validation/phone_rules.dart';
import 'package:nest_fe/core/validation/validators.dart';

/// The shared text input styling. Every form field goes through here so a change to the field
/// shape does not have to be chased across the app.
InputDecoration appInputDecoration(
  AppPalette palette,
  String hint, {
  Widget? prefix,
  bool hasError = false,
  double radius = AppRadii.xl,
}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: AppRadii.all(radius),
        borderSide: BorderSide(color: color),
      );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(fontSize: AppType.lg, fontWeight: AppType.regular, color: palette.textFaint),
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
    filled: true,
    fillColor: palette.surfaceRaised,
    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
    border: border(palette.border),
    enabledBorder: border(hasError ? palette.notPaid : palette.border),
    focusedBorder: border(hasError ? palette.notPaid : palette.primary),
  );
}

/// What a kind of field needs: its keyboard, capitalisation, keystroke filters and the rule its
/// value must satisfy - bundled, so a screen says `FieldPreset.email()` instead of repeating four
/// settings and drifting from the other screens.
///
/// Works on a plain `TextField` too: take [keyboardType], [textCapitalization], [formatters] and
/// [check] from it.
@immutable
class FieldPreset {
  const FieldPreset({
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.formatters = const [],
    this.validator,
    this.autofillHints,
  });

  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter> formatters;
  final Validator? validator;
  final Iterable<String>? autofillHints;

  /// The error for [text] under this preset's rule, or null.
  String? check(String text) => validator?.call(text);

  static FieldPreset personName({String label = 'name', bool required = true, Iterable<String>? hints}) => FieldPreset(
        keyboardType: TextInputType.name,
        textCapitalization: TextCapitalization.words,
        formatters: InputFormats.personName(),
        validator: Validators.personName(label: label, required: required),
        autofillHints: hints,
      );

  static FieldPreset email({bool required = true}) => FieldPreset(
        keyboardType: TextInputType.emailAddress,
        formatters: InputFormats.email(),
        validator: Validators.email(required: required),
        autofillHints: const [AutofillHints.email],
      );

  static FieldPreset username({bool required = true}) => FieldPreset(
        formatters: InputFormats.username(),
        validator: Validators.username(required: required),
        autofillHints: const [AutofillHints.username],
      );

  static FieldPreset title({String label = 'name', int min = 2, int max = 80, bool required = true}) => FieldPreset(
        textCapitalization: TextCapitalization.words,
        formatters: InputFormats.title(max: max),
        validator: Validators.title(label: label, min: min, max: max, required: required),
      );

  static FieldPreset text({String label = 'this', int min = 0, int max = 500, bool required = true}) => FieldPreset(
        textCapitalization: TextCapitalization.sentences,
        formatters: [LengthLimitingTextInputFormatter(max + 50)],
        validator: Validators.text(label: label, min: min, max: max, required: required),
      );

  static FieldPreset amount({String label = 'amount', num? min, num max = 9999999, bool allowZero = false, bool required = true}) =>
      FieldPreset(
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        formatters: InputFormats.amount(),
        validator: Validators.amount(label: label, min: min, max: max, allowZero: allowZero, required: required),
      );

  static FieldPreset wholeNumber({String label = 'number', int min = 0, int max = 1000000, bool required = true}) => FieldPreset(
        keyboardType: TextInputType.number,
        formatters: InputFormats.digits(max: max.toString().length),
        validator: Validators.wholeNumber(label: label, min: min, max: max, required: required),
      );

  static FieldPreset dayOfMonth({bool required = true}) => FieldPreset(
        keyboardType: TextInputType.number,
        formatters: InputFormats.digits(max: 2),
        validator: Validators.dayOfMonth(required: required),
      );

  static FieldPreset percentage({bool required = true}) => FieldPreset(
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        formatters: InputFormats.amount(integerDigits: 3),
        validator: Validators.percentage(required: required),
      );

  static FieldPreset pinCode({String? countryName, bool required = true}) => FieldPreset(
        keyboardType: TextInputType.streetAddress,
        formatters: InputFormats.pinCode(countryName: countryName),
        validator: Validators.pinCode(countryName: countryName, required: required),
        autofillHints: const [AutofillHints.postalCode],
      );

  static FieldPreset url({String label = 'link', bool required = true}) => FieldPreset(
        keyboardType: TextInputType.url,
        formatters: InputFormats.noSpaces(),
        validator: Validators.url(label: label, required: required),
      );

  static FieldPreset linkOrHandle({String label = 'profile', bool required = true}) => FieldPreset(
        keyboardType: TextInputType.url,
        formatters: InputFormats.handleOrLink(),
        validator: Validators.linkOrHandle(label: label, required: required),
      );

  static FieldPreset otp({int min = 4, int max = 8}) => FieldPreset(
        keyboardType: TextInputType.number,
        formatters: InputFormats.digits(max: max),
        validator: Validators.otp(min: min, max: max),
        autofillHints: const [AutofillHints.oneTimeCode],
      );

  static FieldPreset ifsc({bool required = true}) => FieldPreset(
        textCapitalization: TextCapitalization.characters,
        formatters: InputFormats.upperCase(max: 11, allow: RegExp(r'[A-Za-z0-9]')),
        validator: Validators.ifsc(required: required),
      );

  static FieldPreset bankAccount({bool required = true}) => FieldPreset(
        keyboardType: TextInputType.number,
        formatters: InputFormats.digits(max: 18),
        validator: Validators.bankAccount(required: required),
      );

  static FieldPreset upiId({bool required = true}) => FieldPreset(
        keyboardType: TextInputType.emailAddress,
        formatters: InputFormats.noSpaces(max: 320),
        validator: Validators.upiId(required: required),
      );

  static FieldPreset pan({bool required = true}) => FieldPreset(
        textCapitalization: TextCapitalization.characters,
        formatters: InputFormats.upperCase(max: 10, allow: RegExp(r'[A-Za-z0-9]')),
        validator: Validators.pan(required: required),
      );

  static FieldPreset gstin({bool required = true}) => FieldPreset(
        textCapitalization: TextCapitalization.characters,
        formatters: InputFormats.upperCase(max: 15, allow: RegExp(r'[A-Za-z0-9]')),
        validator: Validators.gstin(required: required),
      );
}

/// Decides when a field shows its error, once, for every kind of field.
///
/// A rule is not applied while someone is still typing their first attempt - an email is "wrong" until
/// the last character - but once they leave the field, and from then on as they edit. A screen that
/// wants every error at once (after a failed Save) passes [showErrors]. [builder] draws the field and
/// receives the error to show, or null.
class FieldGuard extends StatefulWidget {
  const FieldGuard({
    super.key,
    required this.controller,
    required this.check,
    required this.builder,
    this.showErrors = false,
  });

  final TextEditingController controller;

  /// Returns the current error, or null. Called whenever it might have changed.
  final String? Function() check;
  final bool showErrors;
  final Widget Function(BuildContext context, String? error) builder;

  @override
  State<FieldGuard> createState() => _FieldGuardState();
}

class _FieldGuardState extends State<FieldGuard> {
  bool _visited = false;

  /// A field is only judged once the person has been in it: focus moving elsewhere (a sheet opening
  /// over it, say) is not "leaving" a field they never touched.
  bool _hadFocus = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(FieldGuard old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    if (mounted && _visited) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.showErrors || _visited ? widget.check() : null;
    return Focus(
      onFocusChange: (focused) {
        if (focused) {
          _hadFocus = true;
        } else if (_hadFocus && !_visited) {
          setState(() => _visited = true);
        }
      },
      child: widget.builder(context, error),
    );
  }
}

/// A text input in the app's style that checks its own value.
///
/// Give it a [preset] (or just a [validator]) and it shows the error under itself, judged when the
/// person leaves the field and live after that (see [FieldGuard]). A screen that wants every error at
/// once (after a failed Save) passes [showErrors]. Without a rule it is the plain styled field it
/// always was.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.keyboardType,
    this.textCapitalization,
    this.inputFormatters,
    this.icon,
    this.hasError = false,
    this.maxLines = 1,
    this.autofocus = false,
    this.focusNode,
    this.onSubmitted,
    this.preset,
    this.validator,
    this.showErrors = false,
    this.obscureText = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final TextCapitalization? textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? icon;
  final bool hasError;
  final int maxLines;
  final bool autofocus;
  final bool obscureText;
  final Widget? suffix;

  /// Keyboard, filters and rule in one. Anything also given explicitly wins over it.
  final FieldPreset? preset;
  final Validator? validator;

  /// Show the error even if the field has not been visited yet.
  final bool showErrors;

  Widget _field(BuildContext context, String? error) {
    final palette = context.palette;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType ?? preset?.keyboardType,
      textCapitalization: textCapitalization ?? preset?.textCapitalization ?? TextCapitalization.none,
      inputFormatters: inputFormatters ?? preset?.formatters,
      autofillHints: preset?.autofillHints,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      autofocus: autofocus,
      style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.medium, color: palette.text),
      decoration: appInputDecoration(
        palette,
        hint,
        hasError: hasError || error != null,
        prefix: icon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.sm),
                child: Icon(icon, size: 15, color: palette.textFaint),
              ),
      ).copyWith(suffixIcon: suffix),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rule = validator ?? preset?.validator;
    if (rule == null) return _field(context, null);
    return FieldGuard(
      controller: controller,
      check: () => rule(controller.text),
      showErrors: showErrors,
      builder: (context, error) {
        final field = _field(context, error);
        if (error == null) return field;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [field, _FieldError(error)],
        );
      },
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(message,
            style: TextStyle(fontSize: AppType.sm, color: context.palette.notPaid, height: 1.4)),
      );
}

/// A phone number: a calling-code button that opens the full searchable list of countries, and a
/// digits field that only takes what is valid for the chosen country.
///
/// The code and the digits are one value, kept in one widget; [dial] (`+91`) is owned by the
/// screen and [controller] holds the national digits. [PhoneRules.format] joins them for saving,
/// [PhoneRules.parseStored] splits a saved number back.
///
/// Pasting a full international number (`+44 7911 123456`) switches the country to match and
/// keeps the rest as the digits.
class PhoneInput extends StatefulWidget {
  const PhoneInput({
    super.key,
    required this.dial,
    required this.controller,
    required this.onDialChanged,
    this.onCountryChanged,
    this.onChanged,
    this.hint,
    this.hasError = false,
    this.kind = PhoneKind.mobile,
    this.required = true,
    this.showErrors = false,
    this.country,
    this.radius = AppRadii.xl,
  });

  final String dial;
  final TextEditingController controller;
  final ValueChanged<String> onDialChanged;

  /// Also told which country was chosen - several share one code (+1), and the number is checked
  /// against that country's rules.
  final ValueChanged<Country>? onCountryChanged;
  final ValueChanged<String>? onChanged;
  final String? hint;
  final bool hasError;

  /// Mobile (can receive an OTP or WhatsApp) or any phone number.
  final PhoneKind kind;
  final bool required;
  final bool showErrors;

  /// The country already chosen, when known (several share +1 and +44); otherwise the main one for
  /// [dial] is assumed.
  final Country? country;

  /// Corner radius of the code button and the digits field; the sign-in screens use pills.
  final double radius;

  @override
  State<PhoneInput> createState() => _PhoneInputState();
}

class _PhoneInputState extends State<PhoneInput> {
  Country? _picked;
  final _digitsFocus = FocusNode();

  @override
  void dispose() {
    _digitsFocus.dispose();
    super.dispose();
  }

  Country get _country {
    final given = widget.country ?? _picked;
    if (given != null && given.dial == widget.dial) return given;
    return Country.forDial(widget.dial) ?? Country.india;
  }

  String? _check() => PhoneRules.validate(
        dial: widget.dial,
        digits: widget.controller.text,
        iso: _country.iso,
        kind: widget.kind,
        required: widget.required,
      );

  Future<void> _pick() async {
    final chosen = await showCountryPicker(context: context, selected: _country);
    if (chosen == null || !mounted) return;
    setState(() => _picked = chosen);
    widget.onDialChanged(chosen.dial);
    widget.onCountryChanged?.call(chosen);
    // Choosing the country is the first half of entering a number; carry on with the digits - but
    // only once the sheet has finished closing. Asking for focus while the route is still leaving
    // makes it bounce straight off again, which would read as having "left" the empty field.
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _digitsFocus.requestFocus();
    });
    // The new country may allow fewer digits than what is already typed.
    final max = PhoneRules.maxDigits(chosen.dial, iso: chosen.iso, kind: widget.kind);
    final typed = widget.controller.text;
    if (typed.length > max) {
      widget.controller.text = typed.substring(0, max);
      widget.onChanged?.call(widget.controller.text);
    }
  }

  /// A pasted `+44 7911 123456` carries its own country: adopt it and keep only the digits.
  TextInputFormatter get _pasteAware => TextInputFormatter.withFunction((old, value) {
        final text = value.text.trim();
        if (!text.startsWith('+') || text.replaceAll(RegExp(r'[^0-9]'), '').length < 5) return value;
        final parsed = PhoneRules.parseStored(text);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _picked = parsed.country);
          widget.onDialChanged(parsed.dial);
          widget.onCountryChanged?.call(parsed.country);
        });
        return TextEditingValue(
          text: parsed.digits,
          selection: TextSelection.collapsed(offset: parsed.digits.length),
        );
      });

  @override
  Widget build(BuildContext context) {
    return FieldGuard(
      controller: widget.controller,
      check: _check,
      showErrors: widget.showErrors,
      builder: _buildInput,
    );
  }

  Widget _buildInput(BuildContext context, String? error) {
    final palette = context.palette;
    final country = _country;
    final hasError = widget.hasError || error != null;
    final max = PhoneRules.maxDigits(widget.dial, iso: country.iso, kind: widget.kind);

    final trigger = Pressable(
      onTap: _pick,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: AppRadii.all(widget.radius),
          border: Border.all(color: hasError ? palette.notPaid : palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(country.flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: AppSpacing.sm),
            Text(country.dial,
                style: TextStyle(fontSize: AppType.xl, fontWeight: AppType.bold, color: palette.text)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 18, color: palette.textFaint),
          ],
        ),
      ),
    );

    final field = TextField(
      controller: widget.controller,
      focusNode: _digitsFocus,
      onChanged: widget.onChanged,
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        _pasteAware,
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(max),
      ],
      style: TextStyle(fontSize: AppType.xxl, fontWeight: AppType.medium, color: palette.text),
      decoration: appInputDecoration(
        palette,
        widget.hint ?? PhoneRules.hint(country, kind: widget.kind),
        hasError: hasError,
        radius: widget.radius,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              trigger,
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: field),
            ],
          ),
        ),
        if (error != null) _FieldError(error),
      ],
    );
  }
}

/// [AppTextField]'s counterpart for screens built from plain Material `TextField`s (labelText
/// style, not the app's pill/outline style): the same presets and the same timing, with the error in
/// Material's own error slot.
class ValidatedTextField extends StatelessWidget {
  const ValidatedTextField({
    super.key,
    required this.controller,
    required this.label,
    this.preset,
    this.validator,
    this.showErrors = false,
    this.onChanged,
    this.helperText,
    this.obscureText = false,
    this.maxLines = 1,
    this.suffixIcon,
    this.textInputAction,
    this.prefixText,
  });

  final TextEditingController controller;
  final String label;
  final FieldPreset? preset;
  final Validator? validator;
  final bool showErrors;
  final ValueChanged<String>? onChanged;
  final String? helperText;
  final bool obscureText;
  final int maxLines;
  final Widget? suffixIcon;
  final String? prefixText;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final rule = validator ?? preset?.validator;
    return FieldGuard(
      controller: controller,
      check: () => rule?.call(controller.text),
      showErrors: showErrors,
      builder: (context, error) => TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: preset?.keyboardType,
        textCapitalization: preset?.textCapitalization ?? TextCapitalization.none,
        inputFormatters: preset?.formatters,
        autofillHints: preset?.autofillHints,
        textInputAction: textInputAction,
        obscureText: obscureText,
        maxLines: obscureText ? 1 : maxLines,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          errorText: error,
          suffixIcon: suffixIcon,
          prefixText: prefixText,
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }
}

/// Adds the shared checking to a `TextField` a screen builds itself (custom decoration, custom
/// layout): wrap it, hand over the controller and a [FieldPreset] (or [rule]), and use the keyboard
/// and filters from the preset on your own field. The error appears under it, judged on leaving the
/// field and live after that; [builder] is told whether there is one, so it can colour its border.
class CheckedField extends StatelessWidget {
  const CheckedField({
    super.key,
    required this.controller,
    required this.builder,
    this.preset,
    this.rule,
    this.showErrors = false,
  });

  final TextEditingController controller;
  final FieldPreset? preset;
  final Validator? rule;
  final bool showErrors;
  final Widget Function(BuildContext context, bool hasError) builder;

  @override
  Widget build(BuildContext context) {
    final check = rule ?? preset?.validator;
    if (check == null) return builder(context, false);
    return FieldGuard(
      controller: controller,
      check: () => check(controller.text),
      showErrors: showErrors,
      builder: (context, error) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [builder(context, error != null), if (error != null) _FieldError(error)],
      ),
    );
  }
}
