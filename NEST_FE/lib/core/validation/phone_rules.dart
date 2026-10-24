import 'package:nest_fe/core/validation/countries.dart';
import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// What a phone field is for. A mobile is something we can send an OTP or a WhatsApp message to,
/// so a landline is refused there; an emergency or alternate contact may be either.
enum PhoneKind { mobile, any }

/// The outcome of checking one number: [error] is null when it is acceptable (or optional and
/// empty); [nsn] is the number to store - the digits with any trunk prefix such as a UK `0`
/// removed.
class PhoneCheck {
  const PhoneCheck({this.error, required this.nsn, this.country});

  final String? error;
  final String nsn;
  final Country? country;

  bool get ok => error == null;
}

/// Per-country phone validation, driven by the libphonenumber metadata - the same rules the
/// backend applies, so a number the app accepts is a number the server accepts.
abstract class PhoneRules {
  /// Checks [digits] (as typed, any separators ignored) against [dial] (`+91`).
  ///
  /// Several countries share some calling codes (`+1` is the US, Canada and 23 others), so with
  /// no [iso] the number passes if it is valid in any of them; with one, only that country's
  /// rules apply.
  static PhoneCheck check({
    required String dial,
    required String digits,
    IsoCode? iso,
    PhoneKind kind = PhoneKind.mobile,
    bool required = true,
  }) {
    final typed = digits.replaceAll(RegExp(r'[^0-9]'), '');
    if (typed.isEmpty) {
      return PhoneCheck(error: required ? 'Enter a phone number.' : null, nsn: '');
    }

    final candidates = _candidates(dial, iso);
    if (candidates.isEmpty) {
      return PhoneCheck(error: 'Choose a country code.', nsn: typed);
    }

    for (final country in candidates) {
      for (final nsn in _variants(country, typed)) {
        if (_valid(country, nsn, kind)) return PhoneCheck(nsn: nsn, country: country);
      }
    }
    return PhoneCheck(error: _explain(candidates, typed, kind), nsn: typed, country: candidates.first);
  }

  /// [check]'s message, for the common case of just needing the error text.
  static String? validate({
    required String dial,
    required String digits,
    IsoCode? iso,
    PhoneKind kind = PhoneKind.mobile,
    bool required = true,
  }) =>
      check(dial: dial, digits: digits, iso: iso, kind: kind, required: required).error;

  /// How many digits to let the user type: the longest valid number for this calling code, plus one
  /// for a trunk prefix they may type out of habit.
  static int maxDigits(String dial, {IsoCode? iso, PhoneKind kind = PhoneKind.any}) {
    var longest = 0;
    for (final country in _candidates(dial, iso)) {
      final lengths = _lengths(country, kind);
      for (final l in lengths) {
        if (l > longest) longest = l;
      }
      if (country.nationalPrefix != null && longest > 0) longest += country.nationalPrefix!.length;
    }
    return longest == 0 ? 15 : longest.clamp(4, 15);
  }

  /// "10 digits", "9 or 10 digits" - shown as the field's hint.
  static String hint(Country country, {PhoneKind kind = PhoneKind.mobile}) {
    final lengths = _lengths(country, kind).toList()..sort();
    if (lengths.isEmpty) return 'Phone number';
    return '${_joinLengths(lengths)} digits';
  }

  /// The form a number is stored in throughout the app: `+91 9876543210`.
  static String format(String dial, String nsn) => nsn.isEmpty ? '' : '$dial $nsn';

  /// Splits a stored value back into its calling code and national digits, and works out which
  /// country it is, so editing re-selects the right one instead of showing the code twice.
  /// Accepts `+91 9876543210`, `+919876543210`, `91 98765 43210` and bare digits (taken as Indian,
  /// which is what an old record without a code means).
  static ({String dial, String digits, Country country}) parseStored(String? stored) {
    final raw = (stored ?? '').trim();
    if (raw.isEmpty) return (dial: Country.india.dial, digits: '', country: Country.india);
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.startsWith('+')) {
      // Longest calling code first (+971 before +97), so Gulf numbers are not mistaken for others.
      for (var len = 3; len >= 1; len--) {
        if (digitsOnly.length <= len) continue;
        final code = digitsOnly.substring(0, len);
        final matches = Country.allForDial(code);
        if (matches.isNotEmpty) {
          final rest = digitsOnly.substring(len);
          return (dial: '+$code', digits: rest, country: _bestFor(matches, rest));
        }
      }
    }
    return (dial: Country.india.dial, digits: digitsOnly, country: Country.india);
  }

  // ---- internals ----

  static List<Country> _candidates(String dial, IsoCode? iso) {
    final all = Country.allForDial(dial);
    if (iso != null) {
      final one = all.where((c) => c.iso == iso).toList();
      if (one.isNotEmpty) return one;
    }
    return all;
  }

  /// Of the countries sharing a code, the one this number is valid in (Canada vs the US), else the
  /// main one.
  static Country _bestFor(List<Country> matches, String nsn) {
    for (final c in matches) {
      for (final v in _variants(c, nsn)) {
        if (_valid(c, v, PhoneKind.any)) return c;
      }
    }
    return matches.first;
  }

  static List<String> _variants(Country country, String typed) {
    final prefix = country.nationalPrefix;
    final out = <String>[typed];
    if (prefix != null && prefix.isNotEmpty && typed.startsWith(prefix) && typed.length > prefix.length) {
      out.add(typed.substring(prefix.length));
    }
    return out;
  }

  static bool _valid(Country country, String nsn, PhoneKind kind) {
    final effective = kind == PhoneKind.mobile && _mobileLengths(country).isEmpty ? PhoneKind.any : kind;
    return PhoneNumber(isoCode: country.iso, nsn: nsn)
        .isValid(type: effective == PhoneKind.mobile ? PhoneNumberType.mobile : null);
  }

  static List<int> _mobileLengths(Country c) => metadataLengthsByIsoCode[c.iso]!.mobile;

  static Set<int> _lengths(Country country, PhoneKind kind) {
    final l = metadataLengthsByIsoCode[country.iso]!;
    if (kind == PhoneKind.mobile && l.mobile.isNotEmpty) return {...l.mobile};
    return {...l.mobile, ...l.fixedLine, ...l.general, ...l.voip, ...l.personalNumber};
  }

  static String _joinLengths(List<int> lengths) {
    if (lengths.length == 1) return '${lengths.first}';
    if (lengths.length == 2) return '${lengths.first} or ${lengths.last}';
    final isRun = [for (var i = 1; i < lengths.length; i++) lengths[i] - lengths[i - 1]].every((d) => d == 1);
    if (isRun) return '${lengths.first} to ${lengths.last}';
    return '${lengths.sublist(0, lengths.length - 1).join(', ')} or ${lengths.last}';
  }

  static String _explain(List<Country> candidates, String typed, PhoneKind kind) {
    final first = candidates.first;
    final label = candidates.length == 1 ? first.name : 'this country code';
    final allowed = <int>{for (final c in candidates) ..._lengths(c, kind)}.toList()..sort();
    // The length the number would have once a trunk prefix it really starts with is dropped.
    final typedLengths = <int>{
      typed.length,
      for (final c in candidates)
        if (c.nationalPrefix != null && typed.startsWith(c.nationalPrefix!)) typed.length - c.nationalPrefix!.length,
    };
    final lengthOk = allowed.any(typedLengths.contains);
    final what = kind == PhoneKind.mobile ? 'mobile number' : 'phone number';
    if (!lengthOk && allowed.isNotEmpty) {
      return candidates.length == 1
          ? '$label $what needs ${_joinLengths(allowed)} digits.'
          : 'A $what for $label needs ${_joinLengths(allowed)} digits.';
    }
    if (first.iso == IsoCode.IN && kind == PhoneKind.mobile) {
      return 'An Indian mobile number starts with 6, 7, 8 or 9.';
    }
    return "That doesn't look like a valid ${candidates.length == 1 ? '$label ' : ''}$what.";
  }
}

extension on Country {
  /// The digit(s) people dial before a number within the country, such as the UK's `0`.
  String? get nationalPrefix => metadataByIsoCode[iso]?.nationalPrefix;
}
