package com.nest.app.notification.entity;

/** The kind of event a notification represents (orthogonal to {@link NotificationModule}, which
 * is about which bell shows it). ADMIN_BROADCAST is a Super Admin announcement composed by hand,
 * platform-wide; ACADEMY_BROADCAST is the same idea one level down - an Academy Admin's message
 * to a resolved audience within their own academy. The rest are system-generated. Room to grow
 * without a schema change as more triggers land. */
public enum NotificationType {
    MEMBERSHIP_CONFIRMATION,
    ADMIN_BROADCAST,
    ACADEMY_BROADCAST
}
