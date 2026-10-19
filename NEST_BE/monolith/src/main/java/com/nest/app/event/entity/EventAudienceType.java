package com.nest.app.event.entity;

/** Who an event targets - metadata only (drives the invited count and audience badge), not a
 * visibility filter: every event stays visible to the whole academy's event list regardless of
 * this value, the same as it is today. */
public enum EventAudienceType {
    ALL_STUDENTS,
    ALL_TRAINERS,
    /** Every active student AND every active trainer - one audience for both, instead of making
     * the admin pick between them. */
    EVERYONE,
    BY_COURSE,
    BY_BATCH,
    INDIVIDUALS
}
