package com.nest.app.event.entity;

/** A cancelled event stays visible (greyed out, restorable) rather than being deleted - the
 * Delete action is separate and permanent. */
public enum EventStatus {
    PUBLISHED,
    DRAFT,
    CANCELLED
}
