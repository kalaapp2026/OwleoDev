package com.nest.app.event.dto;

import com.nest.app.event.entity.EventAudienceType;
import com.nest.app.event.entity.EventType;
import com.nest.app.event.entity.EventVisibility;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Set;
import java.util.UUID;

/** Same shape as CreateEventRequest minus `status` - status changes go through the dedicated
 * PATCH .../status endpoint instead, so an edit can never accidentally cancel/publish an event. */
public record UpdateEventRequest(
        @NotNull EventType type,
        @NotBlank String title,
        String description,
        @NotNull LocalDateTime eventDate,
        LocalDateTime endDate,
        String location,
        String venueMapsUrl,
        @NotNull EventVisibility visibility,
        String coverImageUrl,
        LocalDate interestDeadline,
        EventAudienceType audienceType,
        Set<UUID> courseIds,
        Set<UUID> batchIds,
        Set<UUID> individualIds
) {
}
