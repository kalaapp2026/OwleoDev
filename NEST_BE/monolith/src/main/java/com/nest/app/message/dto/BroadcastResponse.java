package com.nest.app.message.dto;

import com.nest.app.event.entity.EventAudienceType;

import java.time.Instant;
import java.util.Set;
import java.util.UUID;

public record BroadcastResponse(
        UUID id,
        UUID academyId,
        String title,
        String body,
        EventAudienceType audienceType,
        Set<UUID> courseIds,
        Set<UUID> batchIds,
        Set<UUID> individualIds,
        int recipientCount,
        UUID createdBy,
        Instant createdAt
) {
}
