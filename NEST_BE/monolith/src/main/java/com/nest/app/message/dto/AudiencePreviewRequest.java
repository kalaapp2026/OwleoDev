package com.nest.app.message.dto;

import com.nest.app.event.entity.EventAudienceType;
import jakarta.validation.constraints.NotNull;

import java.util.Set;
import java.util.UUID;

/** "How many people would this reach?" - the compose screen's live recipient count. */
public record AudiencePreviewRequest(
        @NotNull EventAudienceType audienceType,
        Set<UUID> courseIds,
        Set<UUID> batchIds,
        Set<UUID> individualIds
) {
}
