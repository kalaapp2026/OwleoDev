package com.nest.app.notification.dto;

import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;

import java.time.Instant;
import java.util.UUID;

public record NotificationResponse(
        UUID id,
        NotificationModule module,
        NotificationType type,
        String title,
        String body,
        String actionCode,
        boolean read,
        Instant createdAt
) {
}
