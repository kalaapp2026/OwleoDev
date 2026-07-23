package com.nest.app.scheduling.entity;

public enum ClassInstanceStatus {
    SCHEDULED,
    HELD,
    CANCELLED,
    /** The original slot a Reschedule moved away from - kept for audit, never deleted (PRD 3.7.2). */
    RESCHEDULED_CANCELLED
}
