import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_gu.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_kn.dart';
import 'app_localizations_ml.dart';
import 'app_localizations_mr.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ta.dart';
import 'app_localizations_te.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('bn'),
    Locale('en'),
    Locale('es'),
    Locale('gu'),
    Locale('hi'),
    Locale('kn'),
    Locale('ml'),
    Locale('mr'),
    Locale('pt'),
    Locale('pt', 'BR'),
    Locale('ta'),
    Locale('te'),
  ];

  /// Subtitle under the logo on the login screen
  ///
  /// In en, this message translates to:
  /// **'Your business. Organized. Automated.'**
  String get appTagline;

  /// Bottom nav: social feed tab
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get navFeed;

  /// No description provided for @navEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get navEvents;

  /// No description provided for @navMyPosts.
  ///
  /// In en, this message translates to:
  /// **'My Posts'**
  String get navMyPosts;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navBatches.
  ///
  /// In en, this message translates to:
  /// **'Batches'**
  String get navBatches;

  /// No description provided for @navFees.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get navFees;

  /// Bottom nav: opens the overflow menu of ERP actions
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// No description provided for @navPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get navPlatform;

  /// No description provided for @navAcademies.
  ///
  /// In en, this message translates to:
  /// **'Academies'**
  String get navAcademies;

  /// No description provided for @navBilling.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get navBilling;

  /// No description provided for @navApplications.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get navApplications;

  /// No description provided for @authUsernameOrMobile.
  ///
  /// In en, this message translates to:
  /// **'Username or mobile number'**
  String get authUsernameOrMobile;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get authContinue;

  /// No description provided for @authLogIn.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get authLogIn;

  /// No description provided for @authLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get authLogOut;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get authFullName;

  /// No description provided for @authUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsername;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// No description provided for @authMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get authMobileNumber;

  /// Label for the one-time confirmation code field
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get authCode;

  /// No description provided for @authVerifyAndLogIn.
  ///
  /// In en, this message translates to:
  /// **'Verify & log in'**
  String get authVerifyAndLogIn;

  /// No description provided for @authResendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get authResendCode;

  /// No description provided for @authChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get authChange;

  /// No description provided for @authLogOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get authLogOutConfirmTitle;

  /// No description provided for @authLogOutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ll need to log in again to continue.'**
  String get authLogOutConfirmMessage;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Shown under the Language row in Settings
  ///
  /// In en, this message translates to:
  /// **'Applies across the whole app'**
  String get settingsLanguageSubtitle;

  /// No description provided for @profileAcademyMemberships.
  ///
  /// In en, this message translates to:
  /// **'Academy memberships'**
  String get profileAcademyMemberships;

  /// No description provided for @profileSuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'Super Admin'**
  String get profileSuperAdmin;

  /// No description provided for @profileYourRole.
  ///
  /// In en, this message translates to:
  /// **'Your role'**
  String get profileYourRole;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get commonLoading;

  /// Form validation message for an empty required field
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get commonRequired;

  /// No description provided for @commonSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonSomethingWentWrong;

  /// No description provided for @commonNoDataYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get commonNoDataYet;

  /// No description provided for @commonCouldNotReachServer.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server - check your connection.'**
  String get commonCouldNotReachServer;

  /// Dashboard greeting, followed by the user's name on the next line
  ///
  /// In en, this message translates to:
  /// **'Welcome back,'**
  String get welcomeBack;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get quickActions;

  /// Dashboard stat: number of active courses in the academy
  ///
  /// In en, this message translates to:
  /// **'Active courses'**
  String get activeCourses;

  /// Dashboard stat shown to students instead of activeCourses
  ///
  /// In en, this message translates to:
  /// **'My courses'**
  String get myCourses;

  /// No description provided for @languageChanged.
  ///
  /// In en, this message translates to:
  /// **'Language updated.'**
  String get languageChanged;

  /// No description provided for @dashWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back,'**
  String get dashWelcomeBack;

  /// No description provided for @dashQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get dashQuickActions;

  /// No description provided for @attTitle.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get attTitle;

  /// No description provided for @attLoadABatchClass.
  ///
  /// In en, this message translates to:
  /// **'Load a batch\'s class'**
  String get attLoadABatchClass;

  /// No description provided for @attClassAdded.
  ///
  /// In en, this message translates to:
  /// **'Class added.'**
  String get attClassAdded;

  /// No description provided for @attNoBatchesForCourse.
  ///
  /// In en, this message translates to:
  /// **'No batches under this course yet.'**
  String get attNoBatchesForCourse;

  /// No description provided for @attLoad.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get attLoad;

  /// No description provided for @attAddAClass.
  ///
  /// In en, this message translates to:
  /// **'Add a class'**
  String get attAddAClass;

  /// No description provided for @attSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit attendance'**
  String get attSubmit;

  /// No description provided for @attSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Attendance submitted.'**
  String get attSubmitted;

  /// No description provided for @fieldCourse.
  ///
  /// In en, this message translates to:
  /// **'Course'**
  String get fieldCourse;

  /// No description provided for @fieldBatch.
  ///
  /// In en, this message translates to:
  /// **'Batch'**
  String get fieldBatch;

  /// No description provided for @fieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get fieldTitle;

  /// No description provided for @fieldDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get fieldDescription;

  /// No description provided for @fieldLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get fieldLocation;

  /// No description provided for @fieldCaption.
  ///
  /// In en, this message translates to:
  /// **'Caption'**
  String get fieldCaption;

  /// No description provided for @socNewPost.
  ///
  /// In en, this message translates to:
  /// **'New post'**
  String get socNewPost;

  /// No description provided for @socPost.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get socPost;

  /// No description provided for @socNeedCaptionOrPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a caption or at least one photo.'**
  String get socNeedCaptionOrPhoto;

  /// No description provided for @socInterested.
  ///
  /// In en, this message translates to:
  /// **'Interested'**
  String get socInterested;

  /// No description provided for @socSearchPeople.
  ///
  /// In en, this message translates to:
  /// **'Search people'**
  String get socSearchPeople;

  /// No description provided for @artistApplicationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Artist Applications'**
  String get artistApplicationsTitle;

  /// No description provided for @actionApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get actionApprove;

  /// No description provided for @actionReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get actionReject;

  /// No description provided for @evtNewEvent.
  ///
  /// In en, this message translates to:
  /// **'New event'**
  String get evtNewEvent;

  /// No description provided for @evtCreateEvent.
  ///
  /// In en, this message translates to:
  /// **'Create event'**
  String get evtCreateEvent;

  /// No description provided for @evtCreated.
  ///
  /// In en, this message translates to:
  /// **'Event created.'**
  String get evtCreated;

  /// No description provided for @evtProgramme.
  ///
  /// In en, this message translates to:
  /// **'Programme'**
  String get evtProgramme;

  /// No description provided for @evtLookingForArtist.
  ///
  /// In en, this message translates to:
  /// **'Looking for Artist'**
  String get evtLookingForArtist;

  /// No description provided for @evtVisibility.
  ///
  /// In en, this message translates to:
  /// **'Visibility:'**
  String get evtVisibility;

  /// No description provided for @evtInHouse.
  ///
  /// In en, this message translates to:
  /// **'In-house'**
  String get evtInHouse;

  /// No description provided for @evtPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get evtPublic;

  /// No description provided for @evtDateTimeHint.
  ///
  /// In en, this message translates to:
  /// **'Date & time (YYYY-MM-DDTHH:mm:ss)'**
  String get evtDateTimeHint;

  /// No description provided for @feedEventBadge.
  ///
  /// In en, this message translates to:
  /// **'EVENT'**
  String get feedEventBadge;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'bn',
    'en',
    'es',
    'gu',
    'hi',
    'kn',
    'ml',
    'mr',
    'pt',
    'ta',
    'te',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'gu':
      return AppLocalizationsGu();
    case 'hi':
      return AppLocalizationsHi();
    case 'kn':
      return AppLocalizationsKn();
    case 'ml':
      return AppLocalizationsMl();
    case 'mr':
      return AppLocalizationsMr();
    case 'pt':
      return AppLocalizationsPt();
    case 'ta':
      return AppLocalizationsTa();
    case 'te':
      return AppLocalizationsTe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
