package com.nest.app.curriculum.entity;

/** Whether students may keep a copy of a file or only open it inside the app. */
public enum StudyMaterialPermission {
    DOWNLOADABLE,
    /** Streamed/rendered in-app with no download affordance. The reason the feature exists: a
     * backing track can be practised against without becoming a redistributable file. */
    VIEW_ONLY
}
