package com.nest.app.message.dto;

import com.nest.app.event.entity.EventAudienceType;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.util.Set;
import java.util.UUID;

/** The audience-targeting shape mirrors {@code CreateEventRequest} exactly - same five audience
 * types, resolved the same way, since a broadcast's "who does this reach" question is identical
 * to an event's. */
public record CreateBroadcastRequest(
        @NotBlank String title,
        @NotBlank String body,
        @NotNull EventAudienceType audienceType,
        Set<UUID> courseIds,
        Set<UUID> batchIds,
        Set<UUID> individualIds
) {
}
