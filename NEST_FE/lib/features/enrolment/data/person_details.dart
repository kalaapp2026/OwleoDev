/// The profile fields the registration form collects beyond name/phone/email.
///
/// One object shared by student and trainer registration because it is literally the same form
/// section - duplicating a dozen fields twice is how the two drift apart.
///
/// Every field is optional. The form marks several as required, but that is a completeness rule
/// about the form, not about the data: a walk-in taken at a counter often has a name and a number
/// and nothing else yet.
class PersonDetails {
  const PersonDetails({
    this.firstName,
    this.lastName,
    this.gender,
    this.bloodGroup,
    this.altPhone,
    this.photoUrl,
    this.addressLine1,
    this.addressLine2,
    this.landmark,
    this.city,
    this.district,
    this.state,
    this.country,
    this.pinCode,
    this.guardianName,
    this.emergencyContact,
    this.qualification,
    this.salary,
    this.joiningDate,
  });

  final String? firstName;
  final String? lastName;
  final String? gender;
  final String? bloodGroup;
  final String? altPhone;
  final String? photoUrl;

  final String? addressLine1;
  final String? addressLine2;
  final String? landmark;
  final String? city;
  final String? district;
  final String? state;
  final String? country;
  final String? pinCode;

  /// Student-only.
  final String? guardianName;
  final String? emergencyContact;

  /// Trainer-only.
  final String? qualification;

  /// Trainer-only. Monthly pay at this academy; null means not recorded, which is not zero.
  final num? salary;

  final DateTime? joiningDate;

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
        'gender': gender,
        'bloodGroup': bloodGroup,
        'altPhone': altPhone,
        'photoUrl': photoUrl,
        'addressLine1': addressLine1,
        'addressLine2': addressLine2,
        'landmark': landmark,
        'city': city,
        'district': district,
        'state': state,
        'country': country,
        'pinCode': pinCode,
        'guardianName': guardianName,
        'emergencyContact': emergencyContact,
        'qualification': qualification,
        'salary': salary,
        'joiningDate': joiningDate == null ? null : isoDate(joiningDate!),
      };

  factory PersonDetails.fromJson(Map<String, dynamic> json) => PersonDetails(
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        gender: json['gender'] as String?,
        bloodGroup: json['bloodGroup'] as String?,
        altPhone: json['altPhone'] as String?,
        photoUrl: json['photoUrl'] as String?,
        addressLine1: json['addressLine1'] as String?,
        addressLine2: json['addressLine2'] as String?,
        landmark: json['landmark'] as String?,
        city: json['city'] as String?,
        district: json['district'] as String?,
        state: json['state'] as String?,
        country: json['country'] as String?,
        pinCode: json['pinCode'] as String?,
        guardianName: json['guardianName'] as String?,
        emergencyContact: json['emergencyContact'] as String?,
        qualification: json['qualification'] as String?,
        salary: json['salary'] as num?,
        joiningDate: json['joiningDate'] == null
            ? null
            : DateTime.tryParse(json['joiningDate'] as String),
      );

  /// `yyyy-MM-dd` - what LocalDate deserialises from. A full ISO instant is rejected, and the
  /// local date-time can shift the day across timezones.
  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// The options the form's gender picker offers.
const genderOptions = ['Male', 'Female', 'Other'];

/// Standard ABO/Rh groups. A fixed list rather than free text: this is the field read out in an
/// emergency, and a typo in it is worse than a blank.
const bloodGroupOptions = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// Dialling codes offered beside a phone field, most common first for this app's users.
class CountryCode {
  const CountryCode(this.code, this.country);

  final String code;
  final String country;

  static const options = [
    CountryCode('+91', 'India'),
    CountryCode('+1', 'US / Canada'),
    CountryCode('+44', 'United Kingdom'),
    CountryCode('+971', 'UAE'),
    CountryCode('+65', 'Singapore'),
    CountryCode('+61', 'Australia'),
  ];

  /// Splits a stored "+91 9876543210" back into its parts so editing re-selects the right country
  /// instead of showing the code twice.
  static ({String code, String digits}) split(String? stored) {
    final raw = (stored ?? '').trim();
    for (final option in options) {
      if (raw.startsWith(option.code)) {
        return (
          code: option.code,
          digits: raw.substring(option.code.length).replaceAll(RegExp(r'[^0-9]'), ''),
        );
      }
    }
    return (code: '+91', digits: raw.replaceAll(RegExp(r'[^0-9]'), ''));
  }
}

/// "Aarav Shah" -> ("Aarav", "Shah"). Used to pre-fill the separate name fields for records
/// saved before those columns existed - everything after the first word is the surname, which is
/// the least-wrong split for a name of any length.
({String firstName, String lastName}) splitName(String? fullName) {
  final parts = (fullName ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return (firstName: '', lastName: '');
  return (firstName: parts.first, lastName: parts.skip(1).join(' '));
}

/// "Aarav Shah" -> "aarav.shah". The suggested login id, editable afterwards.
String slugifyUsername(String name) => name
    .toLowerCase()
    .trim()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '.')
    .replaceAll(RegExp(r'^\.+|\.+$'), '');

/// Whole years since [dob], or null if the date is missing or in the future.
int? ageFrom(DateTime? dob) {
  if (dob == null) return null;
  final now = DateTime.now();
  var age = now.year - dob.year;
  // Not yet had this year's birthday.
  final hadBirthday =
      now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
  if (!hadBirthday) age -= 1;
  return age < 0 ? null : age;
}
