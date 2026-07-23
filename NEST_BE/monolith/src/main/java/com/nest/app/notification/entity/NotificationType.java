package com.nest.app.notification.entity;

/** MEMBERSHIP_CONFIRMATION is the only kind today (PRD 7.4 addendum: the in-app OTP-delivery
 * channel for linking an existing person to a new academy/course) - room to grow without a
 * schema change once real push/social notifications land. */
public enum NotificationType {
    MEMBERSHIP_CONFIRMATION
}
