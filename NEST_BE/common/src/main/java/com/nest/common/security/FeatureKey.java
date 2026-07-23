package com.nest.common.security;

/**
 * Feature catalogue reference list, PRD Section 3.5. These are the values persisted in
 * feature_grants.feature_key and carried as JWT membership claims.
 */
public final class FeatureKey {
    public static final String COURSE_MANAGEMENT = "COURSE_MANAGEMENT";
    public static final String STUDENT_REGISTRATION = "STUDENT_REGISTRATION";
    public static final String TRAINER_REGISTRATION = "TRAINER_REGISTRATION";
    public static final String BATCH_CREATION = "BATCH_CREATION";
    public static final String BATCH_SCHEDULING = "BATCH_SCHEDULING";
    public static final String RESCHEDULE = "RESCHEDULE";
    public static final String ATTENDANCE = "ATTENDANCE";
    public static final String FEES_ENTRY = "FEES_ENTRY";
    public static final String FEES_DASHBOARD = "FEES_DASHBOARD";
    public static final String SYLLABUS_EDIT = "SYLLABUS_EDIT";
    public static final String EVENT_MANAGEMENT = "EVENT_MANAGEMENT";
    public static final String ABOUT_US_EDIT = "ABOUT_US_EDIT";
    /** Trainer-only: lets a Trainer post to Social with an Artist-style card (PRD 3.13). */
    public static final String ARTIST_STYLE_POSTING = "ARTIST_STYLE_POSTING";

    /** Features an Academy Admin may never delegate away, regardless of what they hold (PRD 3.5). */
    public static final java.util.Set<String> NON_DELEGABLE = java.util.Set.of(COURSE_MANAGEMENT, ABOUT_US_EDIT);

    /** Every delegable Trainer feature - what an Academy Admin may grant, since Admin access
     * itself isn't gated by feature_grants rows (PRD 2.2/2.3). */
    public static final java.util.Set<String> ALL_DELEGABLE = java.util.Set.of(
            STUDENT_REGISTRATION, TRAINER_REGISTRATION, BATCH_CREATION, BATCH_SCHEDULING, RESCHEDULE,
            ATTENDANCE, FEES_ENTRY, FEES_DASHBOARD, SYLLABUS_EDIT, EVENT_MANAGEMENT, ARTIST_STYLE_POSTING
    );

    private FeatureKey() {
    }
}
