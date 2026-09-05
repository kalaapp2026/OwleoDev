import 'package:flutter/material.dart';
import 'package:nest_fe/core/auth/feature_keys.dart';

/// The features a trainer can be granted, in the order the form lists them.
///
/// Ordered by how often they are actually handed out rather than alphabetically: attendance and
/// scheduling are what nearly every trainer needs, so they sit at the top and the rare
/// administrative ones sit at the bottom where they read as the exception they are.
///
/// COURSE_MANAGEMENT and ABOUT_US_EDIT are deliberately absent - PRD 3.5 makes them
/// non-delegable, so listing them would only produce a 403 at save time.
const trainerGrantableFeatures = <String>[
  FeatureKeys.attendance,
  FeatureKeys.batchScheduling,
  FeatureKeys.reschedule,
  FeatureKeys.syllabusEdit,
  FeatureKeys.feesEntry,
  FeatureKeys.feesDashboard,
  FeatureKeys.batchCreation,
  FeatureKeys.studentRegistration,
  FeatureKeys.trainerRegistration,
  FeatureKeys.eventManagement,
];

const _labels = <String, String>{
  FeatureKeys.attendance: 'Attendance',
  FeatureKeys.batchScheduling: 'Batch scheduling',
  FeatureKeys.reschedule: 'Reschedule',
  FeatureKeys.syllabusEdit: 'Syllabus & study material',
  FeatureKeys.feesEntry: 'Fees entry',
  FeatureKeys.feesDashboard: 'Fees dashboard',
  FeatureKeys.batchCreation: 'Batch creation',
  FeatureKeys.studentRegistration: 'Student registration',
  FeatureKeys.trainerRegistration: 'Trainer registration',
  FeatureKeys.eventManagement: 'Event management',
};

/// What granting each one actually lets someone do. Without this, the difference between
/// "Fees entry" and "Fees dashboard" is invisible at the moment of granting - and one of the two
/// exposes the whole academy's revenue.
const _descriptions = <String, String>{
  FeatureKeys.attendance: 'Mark and view attendance',
  FeatureKeys.batchScheduling: 'Set and edit the weekly recurring timing',
  FeatureKeys.reschedule: 'Cancel or move a specific class',
  FeatureKeys.syllabusEdit: 'Add and update syllabus, songs and study material',
  FeatureKeys.feesEntry: 'Record a payment for a student',
  FeatureKeys.feesDashboard: 'Course-wide fee analytics - usually kept admin-only',
  FeatureKeys.batchCreation: 'Create batches and assign students',
  FeatureKeys.studentRegistration: 'Add and edit students',
  FeatureKeys.trainerRegistration:
      "Add and edit trainers, capped to this trainer's own permissions",
  FeatureKeys.eventManagement: 'Create in-house and public events',
};

const _icons = <String, IconData>{
  FeatureKeys.attendance: Icons.how_to_reg_outlined,
  FeatureKeys.batchScheduling: Icons.calendar_month_outlined,
  FeatureKeys.reschedule: Icons.event_repeat_outlined,
  FeatureKeys.syllabusEdit: Icons.menu_book_outlined,
  FeatureKeys.feesEntry: Icons.currency_rupee,
  FeatureKeys.feesDashboard: Icons.account_balance_wallet_outlined,
  FeatureKeys.batchCreation: Icons.grid_view_outlined,
  FeatureKeys.studentRegistration: Icons.person_add_alt_outlined,
  FeatureKeys.trainerRegistration: Icons.groups_outlined,
  FeatureKeys.eventManagement: Icons.celebration_outlined,
};

/// Falls back to the raw key with underscores swapped out. That should never surface - it means
/// the backend grew a feature this table has not caught up with - but a readable-ish label beats
/// a blank row.
String featureLabel(String key) => _labels[key] ?? key.replaceAll('_', ' ');

String featureDescription(String key) => _descriptions[key] ?? '';

IconData featureIcon(String key) => _icons[key] ?? Icons.tune;
