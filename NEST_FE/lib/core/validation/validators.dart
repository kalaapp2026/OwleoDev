/// Returns an error message, or null when the value is acceptable.
typedef Validator = String? Function(String value);

/// Field rules, in one place so a name or an email means the same thing on every screen - and in
/// the same words. Each returns null for an acceptable value. Unless it says otherwise a rule
/// treats an empty value as an error; pass `required: false` for an optional field, where empty is
/// fine but anything typed must still be valid.
///
/// The backend applies the same rules (see `FieldRules` there), so a value accepted here is not
/// bounced by the server.
abstract class Validators {
  /// Runs [rules] in order and returns the first error.
  static Validator all(List<Validator> rules) => (value) {
        for (final rule in rules) {
          final error = rule(value);
          if (error != null) return error;
        }
        return null;
      };

  /// Trim and collapse runs of whitespace: what gets stored for a name or a title.
  static String tidy(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String? _blank(String value, String label, bool required) {
    if (value.trim().isEmpty) return required ? 'Enter $label.' : null;
    return null;
  }

  // ---- text ----

  static final _controlChars = RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]');

  /// Free text such as a description or a note: length-bounded, with control characters refused.
  static Validator text({String label = 'this', int min = 0, int max = 500, bool required = true}) => (value) {
        final blank = _blank(value, label, required);
        if (value.trim().isEmpty) return blank;
        if (_controlChars.hasMatch(value)) return 'Remove the unsupported characters from $label.';
        final length = value.trim().length;
        if (length < min) return '${_cap(label)} needs at least $min characters.';
        if (length > max) return '${_cap(label)} can be at most $max characters (it is $length).';
        return null;
      };

  /// A person's name, in any script: letters and combining marks, with spaces between them. No digits,
  /// no punctuation, no symbols.
  static final _personName = RegExp(r'^\p{L}[\p{L}\p{M} ]*$', unicode: true);
  static final _letters = RegExp(r'\p{L}', unicode: true);

  static Validator personName({String label = 'name', int min = 2, int max = 60, bool required = true}) => (value) {
        final blank = _blank(value, label, required);
        if (value.trim().isEmpty) return blank;
        final name = tidy(value);
        if (!_personName.hasMatch(name)) {
          return 'A $label can only have letters and spaces - no numbers or symbols.';
        }
        if (_letters.allMatches(name).length < min) return 'A $label needs at least $min letters.';
        if (name.length > max) return 'A $label can be at most $max characters.';
        return null;
      };

  /// A title of something - a course, a batch, an event, a fee type: letters, digits and the
  /// punctuation such names carry (`& ( ) ' . , / + # : -`).
  static final _title = RegExp(r"^[\p{L}\p{N}][\p{L}\p{N}\p{M} &()'’.,/+#:_-]*$", unicode: true);

  static Validator title({String label = 'name', int min = 2, int max = 80, bool required = true}) => (value) {
        final blank = _blank(value, label, required);
        if (value.trim().isEmpty) return blank;
        final v = tidy(value);
        if (!_title.hasMatch(v)) {
          return "A $label must start with a letter or number and use only letters, numbers and & ( ) ' . , / + # : -";
        }
        if (v.length < min) return 'A $label needs at least $min characters.';
        if (v.length > max) return 'A $label can be at most $max characters.';
        return null;
      };

  // ---- account ----

  /// Practical email check (the HTML living-standard grammar, plus the length limits and a
  /// two-letter-minimum top-level domain). Strict enough to catch `a@b`, `a@@b.com` and spaces;
  /// the real proof an address works is the code we email to it.
  static final _email = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\.[A-Za-z]{2,24}$',
  );

  static Validator email({bool required = true}) => (value) {
        final v = value.trim();
        if (v.isEmpty) return required ? 'Enter an email address.' : null;
        final at = v.indexOf('@');
        final local = at < 0 ? v : v.substring(0, at);
        if (v.length > 254 ||
            local.length > 64 ||
            local.startsWith('.') ||
            local.endsWith('.') ||
            local.contains('..') ||
            !_email.hasMatch(v)) {
          return 'That email address looks incomplete.';
        }
        return null;
      };

  /// 3-30 characters: letters, digits and `. _ -`, starting and ending with a letter or digit.
  static final _username = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9._-]{1,28}[A-Za-z0-9])?$');

  static Validator username({bool required = true}) => (value) {
        final v = value.trim();
        if (v.isEmpty) return required ? 'Pick a username.' : null;
        if (v.length < 3) return 'A username needs at least 3 characters.';
        if (v.length > 30) return 'A username can be at most 30 characters.';
        if (!_username.hasMatch(v)) {
          return 'Use letters, numbers and . _ - only, starting and ending with a letter or number.';
        }
        return null;
      };

  /// At least [min] characters with a letter and a digit, no leading or trailing space, and at most
  /// 72 (the longest password bcrypt reads).
  static Validator password({int min = 8, int max = 72}) => (value) {
        if (value.isEmpty) return 'Enter a password.';
        if (value.length < min) return 'Use at least $min characters.';
        if (value.length > max) return 'Use at most $max characters.';
        if (value != value.trim()) return 'A password cannot start or end with a space.';
        if (!RegExp(r'\p{L}', unicode: true).hasMatch(value) || !RegExp(r'[0-9]').hasMatch(value)) {
          return 'Include at least one letter and one number.';
        }
        return null;
      };

  /// The one-time code emailed or sent to a phone: 4-8 digits.
  static Validator otp({int min = 4, int max = 8}) => (value) {
        final v = value.trim();
        if (v.isEmpty) return 'Enter the code.';
        if (!RegExp('^[0-9]{$min,$max}\$').hasMatch(v)) return 'The code is $min to $max digits.';
        return null;
      };

  // ---- address ----

  /// India's PIN: six digits, the first not zero.
  static final _indianPin = RegExp(r'^[1-9][0-9]{5}$');

  /// A postal code elsewhere: 3-10 letters, digits, spaces or hyphens.
  static final _genericPostal = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 -]{1,8}[A-Za-z0-9]$');

  /// [countryName] picks the rule: India (or unset) is six digits; anything else is looser,
  /// because postal codes differ too much to check precisely.
  static Validator pinCode({String? countryName, bool required = true}) => (value) {
        final v = value.trim();
        if (v.isEmpty) return required ? 'Enter the pin code.' : null;
        final india = countryName == null || countryName.trim().isEmpty || countryName.trim().toLowerCase() == 'india';
        if (india) {
          return _indianPin.hasMatch(v) ? null : 'A pin code is 6 digits and does not start with 0.';
        }
        return _genericPostal.hasMatch(v) ? null : 'That postal code looks wrong.';
      };

  // ---- numbers ----

  /// Money: a positive amount with at most two decimals. Commas typed as thousands separators are
  /// ignored.
  static Validator amount({String label = 'amount', num? min, num max = 9999999, bool allowZero = false, bool required = true}) =>
      (value) {
        final blank = _blank(value, label, required);
        if (value.trim().isEmpty) return blank;
        final v = value.replaceAll(',', '').trim();
        if (!RegExp(r'^[0-9]{1,9}(\.[0-9]{1,2})?$').hasMatch(v)) {
          return 'Enter the $label as a number, with at most 2 decimals.';
        }
        final n = num.parse(v);
        if (n == 0 && !allowZero) return 'The $label must be more than 0.';
        if (min != null && n < min) return 'The $label must be at least $min.';
        if (n > max) return 'The $label can be at most $max.';
        return null;
      };

  /// A whole number between [min] and [max].
  static Validator wholeNumber({String label = 'number', int min = 0, int max = 1000000, bool required = true}) => (value) {
        final blank = _blank(value, label, required);
        if (value.trim().isEmpty) return blank;
        final v = value.trim();
        if (!RegExp(r'^[0-9]{1,9}$').hasMatch(v)) return 'Enter the $label as a whole number.';
        final n = int.parse(v);
        if (n < min || n > max) return 'The $label must be between $min and $max.';
        return null;
      };

  static Validator dayOfMonth({bool required = true}) =>
      wholeNumber(label: 'day of the month', min: 1, max: 31, required: required);

  static Validator percentage({bool required = true}) => (value) {
        if (value.trim().isEmpty) return required ? 'Enter a percentage.' : null;
        final v = value.trim();
        if (!RegExp(r'^[0-9]{1,3}(\.[0-9]{1,2})?$').hasMatch(v)) return 'Enter a percentage like 12.5.';
        return double.parse(v) > 100 ? 'A percentage cannot be more than 100.' : null;
      };

  // ---- links ----

  /// A web address, with or without `https://`: a real host with a top-level domain, no spaces.
  static final _url = RegExp(
    r'^(?:https?://)?(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,24}(?::[0-9]{2,5})?(?:[/?#]\S*)?$',
    caseSensitive: false,
  );

  static Validator url({String label = 'link', bool required = true}) => (value) {
        final v = value.trim();
        if (v.isEmpty) return required ? 'Enter the $label.' : null;
        if (v.length > 2048 || !_url.hasMatch(v)) return 'That $label does not look like a web address.';
        return null;
      };

  /// A social profile given either as a full link or as a handle (`@owleo`, `owleo`).
  static final _handle = RegExp(r'^@?[A-Za-z0-9._]{1,30}$');

  static Validator linkOrHandle({String label = 'profile', bool required = true}) => (value) {
        final v = value.trim();
        if (v.isEmpty) return required ? 'Enter the $label.' : null;
        if (_handle.hasMatch(v) || (v.length <= 2048 && _url.hasMatch(v))) return null;
        return 'Use a link or a handle like @name for the $label.';
      };

  // ---- Indian payment and tax identifiers ----

  static Validator ifsc({bool required = true}) => (value) {
        final v = value.trim().toUpperCase();
        if (v.isEmpty) return required ? 'Enter the IFSC code.' : null;
        return RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(v) ? null : 'An IFSC is 11 characters, like HDFC0001234.';
      };

  static Validator upiId({bool required = true}) => (value) {
        final v = value.trim();
        if (v.isEmpty) return required ? 'Enter the UPI ID.' : null;
        return RegExp(r'^[A-Za-z0-9.\-_]{2,256}@[A-Za-z]{2,64}$').hasMatch(v) ? null : 'A UPI ID looks like name@bank.';
      };

  static Validator bankAccount({bool required = true}) => (value) {
        final v = value.trim();
        if (v.isEmpty) return required ? 'Enter the account number.' : null;
        return RegExp(r'^[0-9]{9,18}$').hasMatch(v) ? null : 'An account number is 9 to 18 digits.';
      };

  static Validator pan({bool required = true}) => (value) {
        final v = value.trim().toUpperCase();
        if (v.isEmpty) return required ? 'Enter the PAN.' : null;
        return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(v) ? null : 'A PAN is 10 characters, like ABCDE1234F.';
      };

  static Validator gstin({bool required = true}) => (value) {
        final v = value.trim().toUpperCase();
        if (v.isEmpty) return required ? 'Enter the GSTIN.' : null;
        return RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(v)
            ? null
            : 'A GSTIN is 15 characters, like 22ABCDE1234F1Z5.';
      };

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
