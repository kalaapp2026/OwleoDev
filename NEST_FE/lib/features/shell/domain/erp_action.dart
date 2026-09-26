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
///
/// Order, labels and icons below deliberately mirror the reference's own MORE_MODULES array
/// (nest-navigation-bar.jsx) tile-for-tile: Courses, Batches, Batch Scheduling, Events, Messages,
/// Study material, Users, Students, Academy profile, Settings - ten tiles, nothing more. Dashboard/
/// Attendance/Fees are deliberately absent from this grid: the reference never duplicates its
/// three bottom-tab items inside "More" (see more_menu_sheet.dart's filter), and Batch Scheduling
/// covers both the schedule feed and reschedule - the reference has no separate reschedule tile,
/// since rescheduling was never a screen of its own, only an action reached from that feed.
const kErpActions = <ErpAction>[
  ErpAction(icon: Icons.add_business_outlined, label: 'Academy Onboarding', route: '/erp/academies/new', superAdminOnly: true),
  ErpAction(icon: Icons.menu_book_outlined, label: 'Courses', route: '/erp/courses', adminOnly: true),
  ErpAction(icon: Icons.layers_outlined, label: 'Batches', route: '/erp/batches', requiredFeature: FeatureKeys.batchCreation),
  ErpAction(icon: Icons.calendar_month_outlined, label: 'Batch Scheduling', route: '/erp/scheduling',
      anyOfFeatures: [FeatureKeys.batchScheduling, FeatureKeys.reschedule]),
  ErpAction(icon: Icons.event_outlined, label: 'Events', route: '/erp/events', requiredFeature: FeatureKeys.eventManagement),
  // adminOnly rather than a feature grant: none of the 13 delegable features maps to "send a
  // broadcast" yet (see BroadcastService's own doc comment) - Trainers still fully receive them.
  ErpAction(icon: Icons.chat_bubble_outline, label: 'Messages', route: '/erp/messages', adminOnly: true),
  // The single materials feature. It absorbed the old course-wide 'Course Materials' syllabus in
  // V29 - the two were the same idea, and a file lives on a batch.
  //
  // No requiredFeature: every Student, Trainer and Admin opens this to read and download. The
  // screen gates upload, edit and delete on SYLLABUS_EDIT internally.
  ErpAction(icon: Icons.description_outlined, label: 'Study Material', route: '/erp/study-materials'),
  ErpAction(icon: Icons.people_outline, label: 'Users', route: '/erp/students/new',
      anyOfFeatures: [FeatureKeys.studentRegistration, FeatureKeys.trainerRegistration]),
  // No requiredFeature - visibility of *content* lives inside the screen (course picker only
  // ever offers courses the caller can see), matching how Study Material's tile already works.
  ErpAction(icon: Icons.school_outlined, label: 'Students', route: '/erp/students'),
  // No adminOnly - every Student/Trainer/Admin can open this to view; the screen itself gates
  // editing on ABOUT_US_EDIT internally (see AcademyInfoScreen's canEdit).
  ErpAction(icon: Icons.apartment_outlined, label: 'Academy Profile', route: '/erp/academy'),
  // Own account password + this academy's plan/invoices - adminOnly rather than a feature grant,
  // since neither is delegable to a Trainer the way COURSE_MANAGEMENT/ABOUT_US_EDIT aren't.
  ErpAction(icon: Icons.tune_outlined, label: 'Settings', route: '/erp/academy-settings', adminOnly: true),
  // The three below are bottom-tab items (see app_shell.dart's _BottomNav), never shown in the
  // More grid - erpTabIndex-bound entries are filtered out there on purpose.
  ErpAction(icon: Icons.grid_view_outlined, label: 'Dashboard', erpTabIndex: 0),
  ErpAction(icon: Icons.fact_check_outlined, label: 'Attendance', erpTabIndex: 1, requiredFeature: FeatureKeys.attendance),
  ErpAction(icon: Icons.account_balance_wallet_outlined, label: 'Fees', erpTabIndex: 3, requiredFeature: FeatureKeys.feesEntry),
];
