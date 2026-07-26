package com.nest.app.notification.entity;

/**
 * Which of the app's two post-login worlds a notification belongs to. The Notifications bell is
 * per-module: the ERP bell only ever shows ERP notifications (fees, classes, membership), the
 * Social bell only ever shows SOCIAL ones (events, posts, engagement) - a Trainer checking their
 * fees dashboard is never interrupted by "someone liked your post", and vice versa.
 */
public enum NotificationModule {
    SOCIAL,
    ERP
}
