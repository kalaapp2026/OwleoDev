package com.nest.app.notification.entity;

/** SKIPPED = we chose not to try (channel not configured, no device, no phone); FAILED = we tried. */
public enum DeliveryStatus {
    SENT,
    FAILED,
    SKIPPED
}
