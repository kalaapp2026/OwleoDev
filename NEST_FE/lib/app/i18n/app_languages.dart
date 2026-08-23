import 'package:flutter/material.dart';

/// The languages the app ships translations for.
///
/// [nativeName] is what the picker shows: someone looking for their own language scans for
/// "தமிழ்", not "Tamil". [englishName] is kept alongside so a support person reading over their
/// shoulder can still identify the row.
enum AppLanguage {
  english('en', null, 'English', 'English'),
  hindi('hi', null, 'हिन्दी', 'Hindi'),
  tamil('ta', null, 'தமிழ்', 'Tamil'),
  telugu('te', null, 'తెలుగు', 'Telugu'),
  bengali('bn', null, 'বাংলা', 'Bengali'),
  marathi('mr', null, 'मराठी', 'Marathi'),
  kannada('kn', null, 'ಕನ್ನಡ', 'Kannada'),
  gujarati('gu', null, 'ગુજરાતી', 'Gujarati'),
  malayalam('ml', null, 'മലയാളം', 'Malayalam'),
  spanish('es', null, 'Español', 'Spanish'),
  arabic('ar', null, 'العربية', 'Arabic'),
  portugueseBrazil('pt', 'BR', 'Português (Brasil)', 'Portuguese (Brazil)');

  const AppLanguage(this.languageCode, this.countryCode, this.nativeName, this.englishName);

  final String languageCode;
  final String? countryCode;
  final String nativeName;
  final String englishName;

  Locale get locale => Locale(languageCode, countryCode);

  /// BCP 47 tag as stored on the user's account ("en", "hi", "pt-BR").
  String get tag => countryCode == null ? languageCode : '$languageCode-$countryCode';

  /// Arabic is the only RTL language here. Flutter derives text direction from the locale
  /// automatically, so this exists for the few places that need to reason about it explicitly
  /// (e.g. a directional icon), not to drive layout.
  bool get isRtl => this == AppLanguage.arabic;

  /// Resolves a stored tag, tolerating case and both separators ("pt-BR", "pt_br"). Anything
  /// unrecognised falls back to English rather than throwing - the backend deliberately doesn't
  /// constrain this column, so an unknown value has to degrade gracefully.
  static AppLanguage fromTag(String? tag) {
    if (tag == null || tag.isEmpty) return AppLanguage.english;
    final normalised = tag.replaceAll('_', '-').toLowerCase();
    for (final language in AppLanguage.values) {
      if (language.tag.toLowerCase() == normalised) return language;
    }
    // "pt-PT" should still land on Portuguese rather than English.
    final base = normalised.split('-').first;
    for (final language in AppLanguage.values) {
      if (language.languageCode == base) return language;
    }
    return AppLanguage.english;
  }

  static List<Locale> get supportedLocales =>
      AppLanguage.values.map((l) => l.locale).toList(growable: false);
}
