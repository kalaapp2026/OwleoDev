package com.nest.app.notification.entity;

/** The kind of event a notification represents (orthogonal to {@link NotificationModule}, which
 * is about which bell shows it). ADMIN_BROADCAST is a Super Admin announcement composed by hand;
 * the rest are system-generated. Room to grow without a schema change as more triggers land. */
public enum NotificationType {
    MEMBERSHIP_CONFIRMATION,
    ADMIN_BROADCAST
}
