package com.nest.app.notification.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.UUID;

/**
 * One row per in-app alert (Notifications tab). {@link #actionCode} carries the OTP for
 * MEMBERSHIP_CONFIRMATION notifications specifically - shown as a distinct chip the recipient
 * reads aloud to whoever's completing the registration, since this channel replaces SMS/WhatsApp
 * for that flow rather than supplementing it.
 */
@Entity
@Table(name = "app_notifications", indexes = {
        @Index(name = "idx_app_notifications_user", columnList = "user_id, created_at")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AppNotification {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    /** Which bell shows this - see {@link NotificationModule}. */
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private NotificationModule module;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private NotificationType type;

    @Column(nullable = false)
    private String title;

    @Column(nullable = false)
    private String body;

    @Column(name = "action_code")
    private String actionCode;

    @Column(name = "read_at")
    private Instant readAt;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;
}
