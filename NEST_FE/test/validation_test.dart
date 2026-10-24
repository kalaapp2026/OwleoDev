import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/core/validation/countries.dart';
import 'package:nest_fe/core/validation/phone_rules.dart';
import 'package:nest_fe/core/validation/validators.dart';
import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

void main() {
  void accepts(Validator rule, List<String> values) {
    for (final v in values) {
      expect(rule(v), isNull, reason: 'should accept "$v"');
    }
  }

  void rejects(Validator rule, List<String> values) {
    for (final v in values) {
      expect(rule(v), isNotNull, reason: 'should reject "$v"');
    }
  }

  group('personName', () {
    final rule = Validators.personName();
    test('accepts letters and spaces, in any script', () {
      accepts(rule, [
        'Aarav',
        'Aarav Shah',
        'आरव शाह', // Devanagari, with combining marks
        'ஆரவ் ஷா', // Tamil
        'José Müller',
        '  Aarav   Shah  ', // surrounding and doubled spaces are tidied, not refused
      ]);
    });
    test('rejects digits, symbols, single letters and empties', () {
      rejects(rule, ['', '   ', 'A', 'Aarav123', 'Aarav@Shah', 'R2D2', '12345', '-Aarav', 'Aarav_Shah', 'A😀B']);
    });
    test('rejects punctuation too: the QA rule is letters only, no special characters', () {
      rejects(rule, ["Shaun O'Neil", 'Mary-Ann', 'A. R. Rahman', 'Dr. Priya Nair', 'Aarav!', 'Aarav,Shah']);
    });
    test('rejects names over the limit', () {
      expect(rule('A' * 61), isNotNull);
      expect(rule('A' * 60), isNull);
    });
    test('optional blank is fine but a bad value is not', () {
      final optional = Validators.personName(required: false);
      expect(optional(''), isNull);
      expect(optional('X1'), isNotNull);
    });
    test('the message names the field', () {
      expect(Validators.personName(label: 'first name')(''), 'Enter first name.');
    });
  });

  group('email', () {
    final rule = Validators.email();
    test('accepts ordinary and unusual-but-valid addresses', () {
      accepts(rule, [
        'a@b.co',
        'name@example.com',
        'first.last@sub.example.co.in',
        'user+tag@example.org',
        "o'brien@example.ie",
        'x_y-z@example-domain.com',
        '123@numbers.io',
      ]);
    });
    test('rejects malformed addresses', () {
      rejects(rule, [
        '',
        'plain',
        'a@b',
        '@example.com',
        'a@@example.com',
        'a b@example.com',
        'a@exa mple.com',
        '.a@example.com',
        'a.@example.com',
        'a..b@example.com',
        'a@example..com',
        'a@-example.com',
        'a@example-.com',
        'a@example.c', // one-letter top-level domain
        'a@example.123',
        'a@.com',
      ]);
    });
    test('enforces the length limits', () {
      expect(rule('${'a' * 64}@example.com'), isNull);
      expect(rule('${'a' * 65}@example.com'), isNotNull);
      expect(rule('a@${'b' * 250}.com'), isNotNull);
    });
    test('optional', () => expect(Validators.email(required: false)(''), isNull));
  });

  group('username', () {
    final rule = Validators.username();
    test('accepts', () => accepts(rule, ['abc', 'aarav.shah', 'Aarav_S', 'a-b-c', 'user123', 'a' * 30]));
    test('rejects', () {
      rejects(rule, ['', 'ab', 'a' * 31, '.abc', 'abc.', '-abc', 'abc_', 'has space', 'ab@cd', 'नाम', 'a/b']);
    });
  });

  group('password', () {
    final rule = Validators.password();
    test('accepts passwords with a letter and a number', () {
      accepts(rule, ['abcd1234', 'Passw0rd', 'a1b2c3d4e5', 'correct horse 9 battery', 'पासवर्ड1234'.replaceAll('पासवर्ड', 'passwordx')]);
    });
    test('rejects short, letter-only, number-only and padded ones', () {
      rejects(rule, ['', 'abc1', 'abcdefgh', '12345678', ' abcdefg1', 'abcdefg1 ', 'a1' * 37]);
    });
    test('72 characters is the ceiling (bcrypt reads no more)', () {
      expect(rule('a1' * 36), isNull);
      expect(rule('${'a1' * 36}x'), isNotNull);
    });
  });

  group('pinCode', () {
    test('India: six digits, not starting with 0', () {
      final rule = Validators.pinCode();
      accepts(rule, ['110001', '560001', '682001']);
      rejects(rule, ['', '012345', '12345', '1234567', '11000a', '110 001']);
    });
    test('an explicit India behaves the same', () {
      expect(Validators.pinCode(countryName: 'india')('110001'), isNull);
      expect(Validators.pinCode(countryName: 'India')('99999'), isNotNull);
    });
    test('elsewhere: a looser postal code', () {
      final rule = Validators.pinCode(countryName: 'United Kingdom');
      accepts(rule, ['SW1A 1AA', 'M1 1AE', '90210', '1010', 'K1A-0B1']);
      rejects(rule, ['', '12', '!!!!!', 'A' * 11]);
    });
  });

  group('amount', () {
    final rule = Validators.amount();
    test('accepts money', () => accepts(rule, ['1', '500', '1500.5', '1500.50', '1,500', '9999999', '0.5']));
    test('rejects non-money', () {
      rejects(rule, ['', '0', '0.00', '-5', '1.234', '1e5', 'abc', '1,2,3x', '10000000', '5.', '.5']);
    });
    test('zero allowed when asked', () => expect(Validators.amount(allowZero: true)('0'), isNull));
    test('minimum and maximum', () {
      expect(Validators.amount(min: 100)('50'), isNotNull);
      expect(Validators.amount(max: 1000)('1001'), isNotNull);
    });
  });

  group('numbers', () {
    test('wholeNumber', () {
      final rule = Validators.wholeNumber(min: 1, max: 60);
      accepts(rule, ['1', '30', '60']);
      rejects(rule, ['', '0', '61', '1.5', '-1', 'a']);
    });
    test('dayOfMonth', () {
      accepts(Validators.dayOfMonth(), ['1', '15', '31']);
      rejects(Validators.dayOfMonth(), ['', '0', '32', 'x']);
    });
    test('percentage', () {
      accepts(Validators.percentage(), ['0', '12.5', '100', '99.99']);
      rejects(Validators.percentage(), ['', '101', '-1', '12.345', 'abc']);
    });
  });

  group('links', () {
    test('url', () {
      final rule = Validators.url();
      accepts(rule, ['https://owleo.in', 'http://example.com/path?x=1', 'www.example.com', 'example.co.in/a/b', 'https://sub.example.org:8080/x']);
      rejects(rule, ['', 'not a url', 'https://', 'http://localhost', 'example', 'ftp://example.com', 'https://exa mple.com', 'javascript:alert(1)']);
    });
    test('linkOrHandle', () {
      final rule = Validators.linkOrHandle();
      accepts(rule, ['@owleo', 'owleo.academy', 'https://instagram.com/owleo', 'instagram.com/owleo']);
      rejects(rule, ['', '@@x', 'has space', 'a' * 31, '@']);
    });
  });

  group('otp', () {
    final rule = Validators.otp();
    test('accepts 4-8 digits', () => accepts(rule, ['1234', '123456', '12345678']));
    test('rejects others', () => rejects(rule, ['', '123', '123456789', '12 34', 'abcd', '12a456']));
  });

  group('payment and tax identifiers', () {
    test('ifsc', () {
      accepts(Validators.ifsc(), ['HDFC0001234', 'sbin0000001']);
      rejects(Validators.ifsc(), ['', 'HDFC1001234', 'HDF0001234', 'HDFC000123', 'HDFC00012345']);
    });
    test('upi', () {
      accepts(Validators.upiId(), ['name@okhdfcbank', 'a.b-c_d@upi', '9876543210@ybl']);
      rejects(Validators.upiId(), ['', 'name', 'name@', '@bank', 'na me@upi', 'name@bank1']);
    });
    test('bank account', () {
      accepts(Validators.bankAccount(), ['123456789', '123456789012345678']);
      rejects(Validators.bankAccount(), ['', '12345678', '1234567890123456789', '12345678a']);
    });
    test('pan', () {
      accepts(Validators.pan(), ['ABCDE1234F', 'abcde1234f']);
      rejects(Validators.pan(), ['', 'ABCDE12345', 'ABCD1234F', 'ABCDE1234']);
    });
    test('gstin', () {
      accepts(Validators.gstin(), ['22ABCDE1234F1Z5', '27AAPFU0939F1ZV']);
      rejects(Validators.gstin(), ['', '22ABCDE1234F1Y5', '22ABCDE1234F1Z', 'ABCDE1234F1Z5']);
    });
  });

  group('title and text', () {
    test('title', () {
      final rule = Validators.title();
      accepts(rule, ['Bharatanatyam', 'Batch A (Morning)', "Kids' Class 2", 'Violin & Piano', 'Grade 1 - Advanced', 'தமிழ் வகுப்பு']);
      rejects(rule, ['', 'A', '(Batch)', '-x', 'Batch <script>', 'a' * 81]);
    });
    test('text bounds and control characters', () {
      final rule = Validators.text(label: 'note', min: 3, max: 10);
      accepts(rule, ['abc', 'a' * 10, 'one\ntwo']);
      rejects(rule, ['', 'ab', 'a' * 11, 'bad\u0000char']);
    });
  });

  group('all', () {
    test('returns the first error and stops', () {
      final rule = Validators.all([
        (v) => v.isEmpty ? 'first' : null,
        (v) => v.length < 3 ? 'second' : null,
      ]);
      expect(rule(''), 'first');
      expect(rule('a'), 'second');
      expect(rule('abc'), isNull);
    });
  });

  group('Country list', () {
    test('covers every region the metadata knows, each with a real name', () {
      expect(Country.all.length, metadataByIsoCode.length);
      expect(Country.all.length, greaterThanOrEqualTo(240));
      for (final c in Country.all) {
        expect(c.name, isNot(c.code), reason: '${c.code} has no display name');
        expect(c.dial, matches(r'^\+[0-9]{1,3}$'));
      }
    });
    test('pinned countries come first, in order, then A to Z', () {
      expect(Country.all.first.iso, IsoCode.IN);
      expect(Country.all[1].iso, IsoCode.US);
      final rest = Country.all.skip(Country.popular.length).map((c) => c.name).toList();
      expect([...rest]..sort(), rest);
    });
    test('well-known dial codes', () {
      final dials = {for (final c in Country.all) c.iso: c.dial};
      expect(dials[IsoCode.IN], '+91');
      expect(dials[IsoCode.US], '+1');
      expect(dials[IsoCode.GB], '+44');
      expect(dials[IsoCode.AE], '+971');
      expect(dials[IsoCode.SG], '+65');
      expect(dials[IsoCode.AU], '+61');
      expect(dials[IsoCode.DE], '+49');
      expect(dials[IsoCode.JP], '+81');
      expect(dials[IsoCode.ZA], '+27');
    });
    test('206 distinct calling codes, and shared ones resolve to a main country', () {
      expect(Country.all.map((c) => c.dial).toSet().length, 206);
      expect(Country.forDial('+1')!.iso, IsoCode.US);
      expect(Country.forDial('+44')!.iso, IsoCode.GB);
      expect(Country.forDial('+91')!.iso, IsoCode.IN);
      expect(Country.forDial('+999'), isNull);
      expect(Country.allForDial('+1').length, greaterThan(20));
    });
    test('flags are built from the two letters', () {
      expect(Country.india.flag, '🇮🇳');
    });
    test('search text finds by name, code and calling code', () {
      final hits = Country.all.where((c) => c.searchText.contains('united')).map((c) => c.iso);
      expect(hits, containsAll([IsoCode.US, IsoCode.GB, IsoCode.AE]));
    });
  });

  group('PhoneRules', () {
    String? mobile(String dial, String digits, {IsoCode? iso}) => PhoneRules.validate(dial: dial, digits: digits, iso: iso);

    test('India: ten digits starting 6-9', () {
      expect(mobile('+91', '9876543210'), isNull);
      expect(mobile('+91', '6000000000'), isNull);
      expect(mobile('+91', '98765 43210'), isNull, reason: 'spaces are ignored');
      expect(mobile('+91', '5876543210'), contains('6, 7, 8 or 9'));
      expect(mobile('+91', '98765'), contains('10 digits'));
      expect(mobile('+91', '98765432101'), contains('10 digits'));
      expect(mobile('+91', ''), 'Enter a phone number.');
    });
    test('India: a landline is refused where a mobile is needed, accepted where any will do', () {
      expect(PhoneRules.validate(dial: '+91', digits: '1123456789'), isNotNull);
      expect(PhoneRules.validate(dial: '+91', digits: '1123456789', kind: PhoneKind.any), isNull);
    });
    test('United States and Canada share +1 but the number must fit one of them', () {
      expect(mobile('+1', '2025550123'), isNull);
      expect(mobile('+1', '4165550123'), isNull); // Toronto
      expect(mobile('+1', '202555012'), isNotNull);
      expect(mobile('+1', '0225550123'), isNotNull, reason: 'area codes do not start with 0');
    });
    test('United Kingdom: a leading 0 is dropped, not counted', () {
      expect(mobile('+44', '7400123456'), isNull);
      final withTrunk = PhoneRules.check(dial: '+44', digits: '07400123456');
      expect(withTrunk.ok, isTrue);
      expect(withTrunk.nsn, '7400123456');
      // 7911 is not a UK range, but it is a Guernsey one, and Guernsey shares +44: so it is refused
      // only once the country is known to be the UK.
      expect(mobile('+44', '7911123456', iso: IsoCode.GB), isNotNull);
      expect(mobile('+44', '7911123456'), isNull);
    });
    test('UAE, Singapore, Australia, Germany, Japan, Brazil, South Africa, Nigeria', () {
      expect(mobile('+971', '501234567'), isNull);
      expect(mobile('+971', '5012345'), isNotNull);
      expect(mobile('+65', '81234567'), isNull);
      expect(mobile('+65', '1234567'), isNotNull);
      expect(mobile('+61', '412345678'), isNull);
      expect(mobile('+49', '15123456789'), isNull);
      expect(mobile('+81', '9012345678'), isNull);
      expect(mobile('+55', '11987654321'), isNull);
      expect(mobile('+27', '821234567'), isNull);
      expect(mobile('+234', '8012345678'), isNull);
    });
    test('an unknown calling code is reported', () {
      expect(mobile('+999', '123456789'), 'Choose a country code.');
    });
    test('optional empty is fine, optional wrong is not', () {
      expect(PhoneRules.validate(dial: '+91', digits: '', required: false), isNull);
      expect(PhoneRules.validate(dial: '+91', digits: '123', required: false), isNotNull);
    });
    test('a specific country overrides the shared code', () {
      // 242 is the Bahamas, so a Canadian-only check refuses it.
      expect(mobile('+1', '2423571234', iso: IsoCode.BS), isNull);
      expect(mobile('+1', '2423571234', iso: IsoCode.CA), isNotNull);
    });
    test('the maximum length typed follows the country', () {
      // Ten digits, plus one for the 0 people habitually type first (it is stripped on save).
      expect(PhoneRules.maxDigits('+91'), 11);
      expect(PhoneRules.maxDigits('+44'), greaterThanOrEqualTo(10));
      expect(PhoneRules.maxDigits('+999'), 15);
    });
    test('hints state the length', () {
      expect(PhoneRules.hint(Country.india), '10 digits');
    });
    test('storage format and round trip', () {
      expect(PhoneRules.format('+91', '9876543210'), '+91 9876543210');
      expect(PhoneRules.format('+91', ''), '');
      for (final stored in ['+91 9876543210', '+919876543210', '+91 98765 43210']) {
        final p = PhoneRules.parseStored(stored);
        expect((p.dial, p.digits, p.country.iso), ('+91', '9876543210', IsoCode.IN), reason: stored);
      }
    });
    test('parseStored handles long codes, shared codes and legacy bare numbers', () {
      final uae = PhoneRules.parseStored('+971 501234567');
      expect((uae.dial, uae.digits, uae.country.iso), ('+971', '501234567', IsoCode.AE));
      final ca = PhoneRules.parseStored('+1 4165550123');
      expect(ca.dial, '+1');
      expect(ca.country.iso, IsoCode.CA, reason: 'a Toronto number belongs to Canada, not the US');
      final legacy = PhoneRules.parseStored('9876543210');
      expect((legacy.dial, legacy.digits), ('+91', '9876543210'));
      final empty = PhoneRules.parseStored(null);
      expect((empty.dial, empty.digits), ('+91', ''));
    });
    test('every country has a calling code that PhoneRules understands', () {
      for (final c in Country.all) {
        final result = PhoneRules.check(dial: c.dial, digits: '1', iso: c.iso);
        expect(result.error, isNotNull, reason: '${c.code}: "1" is never a full number');
        expect(result.country, isNotNull);
      }
    });
    test('every country has at least one number it accepts', () {
      // The libphonenumber example numbers are valid by definition, so this fails if our
      // handling of trunk prefixes or kinds wrongly refuses a real number in some country.
      for (final c in Country.all) {
        final example = metadataExamplesByIsoCode[c.iso]!;
        final nsn = example.mobile.isNotEmpty ? example.mobile : example.fixedLine;
        if (nsn.isEmpty) continue;
        final result = PhoneRules.check(dial: c.dial, digits: nsn, iso: c.iso, kind: PhoneKind.any);
        expect(result.error, isNull, reason: '${c.name} (${c.dial}) example $nsn was refused: ${result.error}');
      }
    });
  });
}
