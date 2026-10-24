import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// One country or territory a phone number can belong to.
///
/// The set, the calling codes and the validity rules all come from the libphonenumber metadata
/// bundled in `phone_numbers_parser`, so they cover every region (245 of them, 206 distinct
/// calling codes) and are exactly the rules the backend checks against. Only the display names are
/// written out here.
class Country {
  const Country._(this.iso, this.name, this.dialDigits, this.isMainForDial);

  final IsoCode iso;
  final String name;

  /// The calling code without the plus: `91`.
  final String dialDigits;

  /// False for e.g. Canada, which shares +1 with the United States.
  final bool isMainForDial;

  /// The calling code as shown and stored: `+91`.
  String get dial => '+$dialDigits';

  /// Two-letter code, `IN`.
  String get code => iso.name;

  /// The flag as an emoji built from the two letters; platforms without flag glyphs (Windows)
  /// show the letters instead, which still reads fine beside the name.
  String get flag => String.fromCharCodes(code.codeUnits.map((c) => 0x1F1E6 + (c - 0x41)));

  /// Lower-cased text the picker's search matches against.
  String get searchText => '$name $code $dial'.toLowerCase();

  /// Countries first offered at the top of the picker: where this app's academies and their
  /// families are, in rough order of how often they are chosen.
  static const _pinned = [
    IsoCode.IN, IsoCode.US, IsoCode.GB, IsoCode.AE, IsoCode.SG, IsoCode.AU, IsoCode.CA, IsoCode.SA,
    IsoCode.QA, IsoCode.KW, IsoCode.OM, IsoCode.BH, IsoCode.MY, IsoCode.NZ, IsoCode.LK, IsoCode.NP,
  ];

  /// Every country, pinned ones first, then A to Z by name.
  static final List<Country> all = _build();

  /// Just the pinned ones, in order.
  static List<Country> get popular => [for (final iso in _pinned) byIso(iso)];

  static final Map<IsoCode, Country> _byIso = {for (final c in all) c.iso: c};

  static Country byIso(IsoCode iso) => _byIso[iso]!;

  static Country get india => byIso(IsoCode.IN);

  /// The country to assume for a bare calling code such as `+1`: the main one for that code.
  /// Null for a code no country uses.
  static Country? forDial(String dial) {
    final digits = dial.replaceAll(RegExp(r'[^0-9]'), '');
    final matches = all.where((c) => c.dialDigits == digits).toList();
    if (matches.isEmpty) return null;
    return matches.firstWhere((c) => c.isMainForDial, orElse: () => matches.first);
  }

  /// Every country that uses [dial] (`+1` is used by 25), main one first.
  static List<Country> allForDial(String dial) {
    final digits = dial.replaceAll(RegExp(r'[^0-9]'), '');
    final matches = all.where((c) => c.dialDigits == digits).toList();
    matches.sort((a, b) => (b.isMainForDial ? 1 : 0) - (a.isMainForDial ? 1 : 0));
    return matches;
  }

  static List<Country> _build() {
    final countries = <Country>[
      for (final entry in metadataByIsoCode.entries)
        Country._(
          entry.key,
          _names[entry.key.name] ?? entry.key.name,
          entry.value.countryCode,
          entry.value.isMainCountryForDialCode,
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    final pinned = [for (final iso in _pinned) countries.firstWhere((c) => c.iso == iso)];
    return [...pinned, ...countries.where((c) => !_pinned.contains(c.iso))];
  }

  /// English display names, by ISO 3166 code. A test checks that none is missing, so a package
  /// update that adds a region fails loudly instead of showing a bare code.
  static const _names = <String, String>{
    'AC': 'Ascension Island', 'AD': 'Andorra', 'AE': 'United Arab Emirates', 'AF': 'Afghanistan',
    'AG': 'Antigua & Barbuda', 'AI': 'Anguilla', 'AL': 'Albania', 'AM': 'Armenia', 'AO': 'Angola',
    'AR': 'Argentina', 'AS': 'American Samoa', 'AT': 'Austria', 'AU': 'Australia', 'AW': 'Aruba',
    'AX': 'Åland Islands', 'AZ': 'Azerbaijan', 'BA': 'Bosnia & Herzegovina', 'BB': 'Barbados',
    'BD': 'Bangladesh', 'BE': 'Belgium', 'BF': 'Burkina Faso', 'BG': 'Bulgaria', 'BH': 'Bahrain',
    'BI': 'Burundi', 'BJ': 'Benin', 'BL': 'St Barthélemy', 'BM': 'Bermuda', 'BN': 'Brunei',
    'BO': 'Bolivia', 'BQ': 'Caribbean Netherlands', 'BR': 'Brazil', 'BS': 'Bahamas', 'BT': 'Bhutan',
    'BW': 'Botswana', 'BY': 'Belarus', 'BZ': 'Belize', 'CA': 'Canada', 'CC': 'Cocos (Keeling) Islands',
    'CD': 'Congo (DRC)', 'CF': 'Central African Republic', 'CG': 'Congo (Republic)', 'CH': 'Switzerland',
    'CI': "Côte d'Ivoire", 'CK': 'Cook Islands', 'CL': 'Chile', 'CM': 'Cameroon', 'CN': 'China',
    'CO': 'Colombia', 'CR': 'Costa Rica', 'CU': 'Cuba', 'CV': 'Cape Verde', 'CW': 'Curaçao',
    'CX': 'Christmas Island', 'CY': 'Cyprus', 'CZ': 'Czechia', 'DE': 'Germany', 'DJ': 'Djibouti',
    'DK': 'Denmark', 'DM': 'Dominica', 'DO': 'Dominican Republic', 'DZ': 'Algeria', 'EC': 'Ecuador',
    'EE': 'Estonia', 'EG': 'Egypt', 'EH': 'Western Sahara', 'ER': 'Eritrea', 'ES': 'Spain',
    'ET': 'Ethiopia', 'FI': 'Finland', 'FJ': 'Fiji', 'FK': 'Falkland Islands', 'FM': 'Micronesia',
    'FO': 'Faroe Islands', 'FR': 'France', 'GA': 'Gabon', 'GB': 'United Kingdom', 'GD': 'Grenada',
    'GE': 'Georgia', 'GF': 'French Guiana', 'GG': 'Guernsey', 'GH': 'Ghana', 'GI': 'Gibraltar',
    'GL': 'Greenland', 'GM': 'Gambia', 'GN': 'Guinea', 'GP': 'Guadeloupe', 'GQ': 'Equatorial Guinea',
    'GR': 'Greece', 'GT': 'Guatemala', 'GU': 'Guam', 'GW': 'Guinea-Bissau', 'GY': 'Guyana',
    'HK': 'Hong Kong', 'HN': 'Honduras', 'HR': 'Croatia', 'HT': 'Haiti', 'HU': 'Hungary',
    'ID': 'Indonesia', 'IE': 'Ireland', 'IL': 'Israel', 'IM': 'Isle of Man', 'IN': 'India',
    'IO': 'British Indian Ocean Territory', 'IQ': 'Iraq', 'IR': 'Iran', 'IS': 'Iceland', 'IT': 'Italy',
    'JE': 'Jersey', 'JM': 'Jamaica', 'JO': 'Jordan', 'JP': 'Japan', 'KE': 'Kenya', 'KG': 'Kyrgyzstan',
    'KH': 'Cambodia', 'KI': 'Kiribati', 'KM': 'Comoros', 'KN': 'St Kitts & Nevis', 'KP': 'North Korea',
    'KR': 'South Korea', 'KW': 'Kuwait', 'KY': 'Cayman Islands', 'KZ': 'Kazakhstan', 'LA': 'Laos',
    'LB': 'Lebanon', 'LC': 'St Lucia', 'LI': 'Liechtenstein', 'LK': 'Sri Lanka', 'LR': 'Liberia',
    'LS': 'Lesotho', 'LT': 'Lithuania', 'LU': 'Luxembourg', 'LV': 'Latvia', 'LY': 'Libya',
    'MA': 'Morocco', 'MC': 'Monaco', 'MD': 'Moldova', 'ME': 'Montenegro', 'MF': 'St Martin',
    'MG': 'Madagascar', 'MH': 'Marshall Islands', 'MK': 'North Macedonia', 'ML': 'Mali', 'MM': 'Myanmar',
    'MN': 'Mongolia', 'MO': 'Macao', 'MP': 'Northern Mariana Islands', 'MQ': 'Martinique',
    'MR': 'Mauritania', 'MS': 'Montserrat', 'MT': 'Malta', 'MU': 'Mauritius', 'MV': 'Maldives',
    'MW': 'Malawi', 'MX': 'Mexico', 'MY': 'Malaysia', 'MZ': 'Mozambique', 'NA': 'Namibia',
    'NC': 'New Caledonia', 'NE': 'Niger', 'NF': 'Norfolk Island', 'NG': 'Nigeria', 'NI': 'Nicaragua',
    'NL': 'Netherlands', 'NO': 'Norway', 'NP': 'Nepal', 'NR': 'Nauru', 'NU': 'Niue', 'NZ': 'New Zealand',
    'OM': 'Oman', 'PA': 'Panama', 'PE': 'Peru', 'PF': 'French Polynesia', 'PG': 'Papua New Guinea',
    'PH': 'Philippines', 'PK': 'Pakistan', 'PL': 'Poland', 'PM': 'St Pierre & Miquelon',
    'PR': 'Puerto Rico', 'PS': 'Palestine', 'PT': 'Portugal', 'PW': 'Palau', 'PY': 'Paraguay',
    'QA': 'Qatar', 'RE': 'Réunion', 'RO': 'Romania', 'RS': 'Serbia', 'RU': 'Russia', 'RW': 'Rwanda',
    'SA': 'Saudi Arabia', 'SB': 'Solomon Islands', 'SC': 'Seychelles', 'SD': 'Sudan', 'SE': 'Sweden',
    'SG': 'Singapore', 'SH': 'St Helena', 'SI': 'Slovenia', 'SJ': 'Svalbard & Jan Mayen',
    'SK': 'Slovakia', 'SL': 'Sierra Leone', 'SM': 'San Marino', 'SN': 'Senegal', 'SO': 'Somalia',
    'SR': 'Suriname', 'SS': 'South Sudan', 'ST': 'São Tomé & Príncipe', 'SV': 'El Salvador',
    'SX': 'Sint Maarten', 'SY': 'Syria', 'SZ': 'Eswatini', 'TA': 'Tristan da Cunha',
    'TC': 'Turks & Caicos Islands', 'TD': 'Chad', 'TG': 'Togo', 'TH': 'Thailand', 'TJ': 'Tajikistan',
    'TK': 'Tokelau', 'TL': 'Timor-Leste', 'TM': 'Turkmenistan', 'TN': 'Tunisia', 'TO': 'Tonga',
    'TR': 'Türkiye', 'TT': 'Trinidad & Tobago', 'TV': 'Tuvalu', 'TW': 'Taiwan', 'TZ': 'Tanzania',
    'UA': 'Ukraine', 'UG': 'Uganda', 'US': 'United States', 'UY': 'Uruguay', 'UZ': 'Uzbekistan',
    'VA': 'Vatican City', 'VC': 'St Vincent & Grenadines', 'VE': 'Venezuela',
    'VG': 'British Virgin Islands', 'VI': 'US Virgin Islands', 'VN': 'Vietnam', 'VU': 'Vanuatu',
    'WF': 'Wallis & Futuna', 'WS': 'Samoa', 'XK': 'Kosovo', 'YE': 'Yemen', 'YT': 'Mayotte',
    'ZA': 'South Africa', 'ZM': 'Zambia', 'ZW': 'Zimbabwe',
  };
}
