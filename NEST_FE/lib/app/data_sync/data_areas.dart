import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/features/academy/data/academy_billing_api.dart';
import 'package:nest_fe/features/academy/data/academy_settings_api.dart';
import 'package:nest_fe/features/academy/presentation/academy_onboarding_screen.dart';
import 'package:nest_fe/features/academy/presentation/academy_profile_shared.dart';
import 'package:nest_fe/features/artist_application/presentation/artist_applications_screen.dart';
import 'package:nest_fe/features/attendance/data/attendance_api.dart';
import 'package:nest_fe/features/curriculum/data/curriculum_api.dart';
import 'package:nest_fe/features/curriculum/data/study_material_api.dart';
import 'package:nest_fe/features/dashboard/data/dashboard_api.dart';
import 'package:nest_fe/features/enrolment/data/enrolment_api.dart';
import 'package:nest_fe/features/fees/data/fees_api.dart';
import 'package:nest_fe/features/messages/data/messages_api.dart';
import 'package:nest_fe/features/notification/presentation/notifications_screen.dart';
import 'package:nest_fe/features/platform/data/notification_templates_api.dart';
import 'package:nest_fe/features/platform/data/platform_settings_api.dart';
import 'package:nest_fe/features/platform/presentation/billing_screen.dart';
import 'package:nest_fe/features/platform/presentation/super_admin_dashboard_screen.dart';
import 'package:nest_fe/features/profile/data/self_profile_api.dart';
import 'package:nest_fe/features/scheduling/data/calendar_api.dart';
import 'package:nest_fe/features/scheduling/data/scheduling_api.dart';
import 'package:nest_fe/features/social/presentation/events_tab.dart';
import 'package:nest_fe/features/social/presentation/feed_screen.dart';
import 'package:nest_fe/features/social/presentation/search_profiles_screen.dart';

typedef Apis = Set<ProviderBase<Object?>>;

/// Which data a write can change, in terms of the API providers that read it.
///
/// A provider is "in" an area if it watches one of that area's API providers (every data provider
/// in the app does, so none of them need annotating). When a write to `/students/...` succeeds,
/// [forSegment] says which API providers' readers might now be showing old data, and DataSync
/// refetches exactly those.
///
/// The sets are deliberately generous: people, batches and courses feed nearly every academy screen,
/// so changing one refreshes them all. The cost of a surplus refetch is one request; the cost of
/// a missing one is a screen that lies until someone hard-reloads.
class DataAreas {
  DataAreas._();

  /// The first path segment, which names the area: `/students/3f2/fees` -> `students`.
  static String segmentOf(String path) {
    final parts = path.split('?').first.split('/').where((p) => p.isNotEmpty);
    return parts.isEmpty ? '' : parts.first;
  }

  /// Everything that shows who is in an academy and how it is organised.
  static Apis get _academyCore => {
        enrolmentApiProvider,
        curriculumApiProvider,
        attendanceApiProvider,
        feesApiProvider,
        schedulingApiProvider,
        calendarApiProvider,
        dashboardApiProvider,
        selfProfileApiProvider,
        studyMaterialApiProvider,
        academyProfileApiProvider,
        peopleSearchApiProvider,
        eventsApiProvider,
        messagesApiProvider,
      };

  static Apis get _platform => {
        platformApiProvider,
        billingApiProvider,
        platformSettingsApiProvider,
        notificationTemplatesApiProvider,
        notificationApiProvider,
        artistApplicationApiProvider,
        academyBillingApiProvider,
        academySettingsApiProvider,
        academyOnboardingApiProvider,
        dashboardApiProvider,
      };

  /// The API providers affected by a write under [segment], or null when the segment is not one
  /// we know - the caller then refreshes everything on screen.
  static Apis? forSegment(String segment) {
    switch (segment) {
      case 'students':
      case 'trainers':
      case 'users':
      case 'existing-accounts':
      case 'batches':
      case 'courses':
        return _academyCore;
      case 'class-instances':
      case 'schedule':
      case 'schedules':
      case 'calendar':
        return {schedulingApiProvider, calendarApiProvider, attendanceApiProvider, dashboardApiProvider};
      case 'fees':
        return {feesApiProvider, dashboardApiProvider, selfProfileApiProvider};
      case 'study-materials':
      case 'material-playlists':
        return {studyMaterialApiProvider, dashboardApiProvider};
      case 'academies':
        return {
          ...{
            academyProfileApiProvider,
            academySettingsApiProvider,
            academyBillingApiProvider,
            academyOnboardingApiProvider,
            messagesApiProvider,
            eventsApiProvider,
            dashboardApiProvider,
            enrolmentApiProvider,
            billingApiProvider,
          },
        };
      case 'events':
      case 'interests':
        return {eventsApiProvider, socialApiProvider, dashboardApiProvider};
      case 'posts':
      case 'feed':
        return {socialApiProvider};
      case 'notifications':
        return {notificationApiProvider};
      case 'artist-applications':
        return {artistApplicationApiProvider, notificationApiProvider, selfProfileApiProvider};
      case 'me':
        // The caller's own record: profile, their fees, their courses and classes.
        return {
          selfProfileApiProvider,
          feesApiProvider,
          curriculumApiProvider,
          dashboardApiProvider,
          enrolmentApiProvider,
          attendanceApiProvider,
        };
      case 'admin':
      case 'platform':
        return _platform;
      default:
        return null;
    }
  }

  /// What a tab shows, for refreshing it when it is opened.
  static Apis forTab({
    required bool erp,
    required int index,
    required bool isStudent,
    required bool isSuperAdmin,
  }) {
    if (!erp) {
      switch (index) {
        case 0:
        case 3:
          return {socialApiProvider};
        case 1:
          return {eventsApiProvider};
        case 4:
          return {selfProfileApiProvider};
        default:
          return {};
      }
    }
    if (isSuperAdmin) return _platform;
    switch (index) {
      case 0: // Dashboard: schedule, stats, dues, events, latest material
        return {
          dashboardApiProvider,
          curriculumApiProvider,
          feesApiProvider,
          eventsApiProvider,
          schedulingApiProvider,
          calendarApiProvider,
          studyMaterialApiProvider,
          enrolmentApiProvider,
          attendanceApiProvider,
          selfProfileApiProvider,
        };
      case 1:
        return {attendanceApiProvider, enrolmentApiProvider, schedulingApiProvider, curriculumApiProvider, calendarApiProvider};
      case 3:
        return {feesApiProvider, curriculumApiProvider, enrolmentApiProvider};
      case 4:
        return {selfProfileApiProvider, academyProfileApiProvider};
      default:
        return {};
    }
  }
}
