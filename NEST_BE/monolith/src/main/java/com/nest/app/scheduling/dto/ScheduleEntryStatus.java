package com.nest.app.scheduling.dto;

/**
 * How a schedule row should read to the person looking at it.
 *
 * <p>Deliberately a presentation vocabulary, not a copy of
 * {@link com.nest.app.scheduling.entity.ClassInstanceStatus}. The stored status says what happened
 * to the record; this says what the reader needs to understand. A rescheduled class is one stored
 * pair but two rows here, and a substitution is not a stored status at all - it is a SCHEDULED
 * instance that happens to carry a substitute.
 */
public enum ScheduleEntryStatus {
    /** Going ahead as planned. */
    SCHEDULED,

    /** Going ahead, but someone else is covering it. */
    SWAPPED,

    /** Lands on this date, having been moved here from another one. */
    MOVED_IN,

    /** The date this session was originally on, kept visible so it doesn't just disappear. */
    MOVED_OUT,

    /** Not happening. Stays on the feed with its reason rather than being removed. */
    CANCELLED,

    /** Already taught. */
    HELD
}
