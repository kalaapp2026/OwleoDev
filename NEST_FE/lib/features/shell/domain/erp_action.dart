import 'package:flutter/material.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/user_profile.dart';

class ErpAction {
  final IconData icon;
  final String label;
  final String? route;
  final int? erpTabIndex;
  final String? requiredFeature;
  final bool adminOnly;

  const ErpAction({
    required this.icon,
    required this.label,
    this.route,
    this.erpTabIndex,
    this.requiredFeature,
    this.adminOnly = false,
  });

  bool visibleFor(UserProfile user) {
    if (adminOnly) return user.isSuperAdmin || user.isActiveAcademyAdmin;
    if (requiredFeature == null) return true;
    return user.isSuperAdmin || user.isActiveAcademyAdmin || user.hasFeature(requiredFeature!);
  }
}

/// Single source of truth for "what ERP actions can this person see" - both the Dashboard's
/// tile grid and the More bottom sheet render from this same list, so they can never drift.
/// PRD 3.1: the ERP home screen only ever shows tiles the caller's role+feature grants allow.
const kErpActions = <ErpAction>[
  ErpAction(icon: Icons.celebration_outlined, label: 'Event Creation', route: '/erp/events/new', requiredFeature: FeatureKeys.eventManagement),
  // No requiredFeature - every Student/Trainer/Admin can open this to read/download; the screen
  // itself gates create/edit/delete on SYLLABUS_EDIT internally (see SyllabusScreen's canEdit).
  ErpAction(icon: Icons.menu_book_outlined, label: 'Course Materials', route: '/erp/syllabus'),
  ErpAction(icon: Icons.badge_outlined, label: 'About Instructor', route: '/profile'),
  // No adminOnly - every Student/Trainer/Admin can open this to view; the screen itself gates
  // editing on ABOUT_US_EDIT internally (see AcademyInfoScreen's canEdit).
  ErpAction(icon: Icons.account_balance_outlined, label: 'About Institute', route: '/erp/academy'),
  ErpAction(icon: Icons.auto_stories_outlined, label: 'Course Creation', route: '/erp/courses', adminOnly: true),
  ErpAction(icon: Icons.groups_2_outlined, label: 'Batch Creation', erpTabIndex: 1, requiredFeature: FeatureKeys.batchCreation),
  ErpAction(icon: Icons.event_note_outlined, label: 'Class Schedule', route: '/erp/scheduling', requiredFeature: FeatureKeys.batchScheduling),
  ErpAction(icon: Icons.update_outlined, label: 'Class Reschedule', route: '/erp/scheduling/reschedule', requiredFeature: FeatureKeys.reschedule),
  ErpAction(icon: Icons.person_add_alt_outlined, label: 'User Creation', route: '/erp/students/new', requiredFeature: FeatureKeys.studentRegistration),
  ErpAction(icon: Icons.grid_view_outlined, label: 'Dashboard', erpTabIndex: 0),
  ErpAction(icon: Icons.fact_check_outlined, label: 'Attendance', route: '/erp/attendance', requiredFeature: FeatureKeys.attendance),
  ErpAction(icon: Icons.calendar_month_outlined, label: 'Calendar', route: '/erp/calendar'),
  ErpAction(icon: Icons.account_balance_wallet_outlined, label: 'Wallet', erpTabIndex: 3, requiredFeature: FeatureKeys.feesEntry),
];
