package com.nest.app.notification.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

/** The Super Admin's wording and channel choices for one {@link NotificationEvent}. */
@Entity
@Table(name = "notification_templates")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class NotificationTemplate {

    @Id
    @GeneratedValue
    private UUID id;

    /** {@link NotificationEvent#name()}. Stored as text so retiring an event never breaks loading. */
    @Column(name = "event_key", nullable = false, unique = true, length = 60)
    private String eventKey;

    @Column(name = "title_template", nullable = false, length = 200)
    private String titleTemplate;

    @Column(name = "body_template", nullable = false, length = 1000)
    private String bodyTemplate;

    @Column(name = "in_app_enabled", nullable = false)
    private boolean inAppEnabled;

    @Column(name = "push_enabled", nullable = false)
    private boolean pushEnabled;

    @Column(name = "whatsapp_enabled", nullable = false)
    private boolean whatsappEnabled;

    @Column(name = "whatsapp_template_name", length = 120)
    private String whatsappTemplateName;

    @Column(nullable = false)
    private boolean enabled;

    @Column(name = "updated_by")
    private UUID updatedBy;

    @Column(name = "created_at", nullable = false, updatable = false)
    @Builder.Default
    private Instant createdAt = Instant.now();

    @Column(name = "updated_at", nullable = false)
    @Builder.Default
    private Instant updatedAt = Instant.now();
}
