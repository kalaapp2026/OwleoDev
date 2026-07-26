package com.nest.app.notification.dto;

import com.nest.app.notification.entity.NotificationModule;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.util.UUID;

/**
 * A Super Admin hand-composed announcement. {@link #module} decides which bell it lands in (Social
 * or ERP). {@link #audience} is EVERYONE (all users) or ACADEMY (every member of {@link #academyId}).
 */
public record BroadcastRequest(
        @NotNull NotificationModule module,
        @NotNull BroadcastAudience audience,
        /** Required only when audience == ACADEMY. */
        UUID academyId,
        @NotBlank String title,
        @NotBlank String body
) {
    public enum BroadcastAudience {
        EVERYONE,
        ACADEMY
    }
}
