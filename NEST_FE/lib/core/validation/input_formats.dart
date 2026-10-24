import 'package:flutter/services.dart';

/// Keystroke filters that match the rules in `Validators`: they stop characters a field can never
/// accept from being typed or pasted, so the common mistakes never reach the error message.
///
/// They only remove what is never valid. Whether what is left is *acceptable* (long enough,
/// well-formed) is still the validator's call.
abstract class InputFormats {
  static List<TextInputFormatter> digits({int? max}) => [
        FilteringTextInputFormatter.digitsOnly,
        if (max != null) LengthLimitingTextInputFormatter(max),
      ];

  /// Only the length is capped. A digit or symbol typed in a name is NOT silently dropped: it stays in
  /// the box with the validator's message under it, so the person sees why and fixes it (and Save stays
  /// off until they do).
  static List<TextInputFormatter> personName({int max = 60}) => [
        LengthLimitingTextInputFormatter(max),
      ];

  /// Letters, digits and the punctuation names of courses, batches and events carry.
  static List<TextInputFormatter> title({int max = 80}) => [
        FilteringTextInputFormatter.allow(RegExp(r"[\p{L}\p{N}\p{M} &()'’.,/+#:_-]", unicode: true)),
        LengthLimitingTextInputFormatter(max),
      ];

  static List<TextInputFormatter> username({int max = 30}) => [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._-]')),
        LengthLimitingTextInputFormatter(max),
      ];

  /// No whitespace anywhere (an address never has any, and a pasted one often trails a space).
  static List<TextInputFormatter> email({int max = 254}) => [
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
        LengthLimitingTextInputFormatter(max),
      ];

  static List<TextInputFormatter> noSpaces({int max = 2048}) => [
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
        LengthLimitingTextInputFormatter(max),
      ];

  /// Money: digits with at most two decimals. Rejects a keystroke that would break the shape
  /// rather than altering it, so the caret never jumps.
  static List<TextInputFormatter> amount({int integerDigits = 9, int decimals = 2}) => [
        _ShapeFormatter(RegExp('^[0-9]{0,$integerDigits}(\\.[0-9]{0,$decimals})?\$')),
      ];

  static List<TextInputFormatter> pinCode({String? countryName}) {
    final india = countryName == null || countryName.trim().isEmpty || countryName.trim().toLowerCase() == 'india';
    return india
        ? digits(max: 6)
        : [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
            LengthLimitingTextInputFormatter(10),
          ];
  }

  static List<TextInputFormatter> upperCase({int? max, RegExp? allow}) => [
        if (allow != null) FilteringTextInputFormatter.allow(allow),
        if (max != null) LengthLimitingTextInputFormatter(max),
        TextInputFormatter.withFunction((old, value) => value.copyWith(text: value.text.toUpperCase())),
      ];

  static List<TextInputFormatter> handleOrLink({int max = 2048}) => noSpaces(max: max);
}

/// Accepts a change only if the whole new text still matches [shape].
class _ShapeFormatter extends TextInputFormatter {
  _ShapeFormatter(this.shape);

  final RegExp shape;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      shape.hasMatch(newValue.text) ? newValue : oldValue;
}
