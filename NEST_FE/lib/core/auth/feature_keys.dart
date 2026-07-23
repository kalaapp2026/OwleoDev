/// Mirrors backend com.nest.common.security.FeatureKey exactly - these strings must match
/// what's stored in feature_grants.feature_key and carried in the JWT.
class FeatureKeys {
  FeatureKeys._();

  static const courseManagement = 'COURSE_MANAGEMENT';
  static const studentRegistration = 'STUDENT_REGISTRATION';
  static const trainerRegistration = 'TRAINER_REGISTRATION';
  static const batchCreation = 'BATCH_CREATION';
  static const batchScheduling = 'BATCH_SCHEDULING';
  static const reschedule = 'RESCHEDULE';
  static const attendance = 'ATTENDANCE';
  static const feesEntry = 'FEES_ENTRY';
  static const feesDashboard = 'FEES_DASHBOARD';
  static const syllabusEdit = 'SYLLABUS_EDIT';
  static const eventManagement = 'EVENT_MANAGEMENT';
  static const aboutUsEdit = 'ABOUT_US_EDIT';
  static const artistStylePosting = 'ARTIST_STYLE_POSTING';
}
