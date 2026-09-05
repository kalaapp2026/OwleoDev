import 'package:flutter/material.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/user_profile.dart';

class ErpAction {
  final IconData icon;
  final String label;
  final String? route;
  final int? erpTabIndex;
  final String? requiredFeature;
  /// Alternative to [requiredFeature] for a tile that covers more than one delegable action
  /// (e.g. "User Creation" covers both Student and Trainer registration) - visible if the caller
  /// holds ANY of these, since the screen behind the tile shows only the parts they can use.
  final List<String>? anyOfFeatures;
  final bool adminOnly;
  final bool superAdminOnly;

  const ErpAction({
    required this.icon,
    required this.label,
    this.route,
    this.erpTabIndex,
    this.requiredFeature,
    this.anyOfFeatures,
    this.adminOnly = false,
    this.superAdminOnly = false,
  });

  bool visibleFor(UserProfile user) {
    // Cross-tenant platform actions (academy onboarding) - only a Super Admin, who has no academy
    // membership of their own, ever sees these.
    if (superAdminOnly) return user.isSuperAdmin;

    // Everything else operates INSIDE one academy the caller belongs to. A Super Admin has no such
    // membership, so none of these apply to them - showing them would just surface tiles that fail
    // the moment they're tapped (no active academy to scope the request to).
    if (user.isSuperAdmin) return false;
    if (adminOnly) return user.isActiveAcademyAdmin;
    if (anyOfFeatures != null) {
      return user.isActiveAcademyAdmin || anyOfFeatures!.any(user.hasFeature);
    }
    if (requiredFeature == null) return true;
    return user.isActiveAcademyAdmin || user.hasFeature(requiredFeature!);
  }
}

/// Single source of truth for "what ERP actions can this person see" - both the Dashboard's
/// tile grid and the More bottom sheet render from this same list, so they can never drift.
/// PRD 3.1: the ERP home screen only ever shows tiles the caller's role+feature grants allow.
const kErpActions = <ErpAction>[
  ErpAction(icon: Icons.add_business_outlined, label: 'Academy Onboarding', route: '/erp/academies/new', superAdminOnly: true),
  ErpAction(icon: Icons.celebration_outlined, label: 'Event Creation', route: '/erp/events/new', requiredFeature: FeatureKeys.eventManagement),
  ErpAction(icon: Icons.badge_outlined, label: 'About Instructor', route: '/profile'),
  // No adminOnly - every Student/Trainer/Admin can open this to view; the screen itself gates
  // editing on ABOUT_US_EDIT internally (see AcademyInfoScreen's canEdit).
  ErpAction(icon: Icons.account_balance_outlined, label: 'About Institute', route: '/erp/academy'),
  ErpAction(icon: Icons.auto_stories_outlined, label: 'Course Creation', route: '/erp/courses', adminOnly: true),
  ErpAction(icon: Icons.groups_2_outlined, label: 'Batch Creation', erpTabIndex: 1, requiredFeature: FeatureKeys.batchCreation),
  ErpAction(icon: Icons.event_note_outlined, label: 'Class Schedule', route: '/erp/scheduling', requiredFeature: FeatureKeys.batchScheduling),
  // Rescheduling no longer has a screen of its own - it is an action on the class it applies to,
  // reached from the schedule feed. This entry stays because someone whose job is rescheduling
  // looks for that word, and it lands them on the feed where the action lives.
  ErpAction(icon: Icons.update_outlined, label: 'Class Reschedule', route: '/erp/scheduling', requiredFeature: FeatureKeys.reschedule),
  // The single materials feature. It absorbed the old course-wide 'Course Materials' syllabus in
  // V29 - the two were the same idea, and a file lives on a batch.
  //
  // No requiredFeature: every Student, Trainer and Admin opens this to read and download. The
  // screen gates upload, edit and delete on SYLLABUS_EDIT internally.
  ErpAction(icon: Icons.folder_shared_outlined, label: 'Study Material', route: '/erp/study-materials'),
  ErpAction(icon: Icons.person_add_alt_outlined, label: 'User Creation', route: '/erp/students/new',
      anyOfFeatures: [FeatureKeys.studentRegistration, FeatureKeys.trainerRegistration]),
  ErpAction(icon: Icons.grid_view_outlined, label: 'Dashboard', erpTabIndex: 0),
  ErpAction(icon: Icons.fact_check_outlined, label: 'Attendance', route: '/erp/attendance', requiredFeature: FeatureKeys.attendance),
  ErpAction(icon: Icons.calendar_month_outlined, label: 'Calendar', route: '/erp/calendar'),
  ErpAction(icon: Icons.account_balance_wallet_outlined, label: 'Wallet', erpTabIndex: 3, requiredFeature: FeatureKeys.feesEntry),
];
