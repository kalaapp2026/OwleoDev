package com.nest.app.event.dto;

import com.nest.app.event.entity.EventAudienceType;
import com.nest.app.event.entity.EventStatus;
import com.nest.app.event.entity.EventType;
import com.nest.app.event.entity.EventVisibility;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Set;

public record CreateEventRequest(
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
        /** Defaults to PUBLISHED when absent - every event before this field existed was
         * effectively published immediately. */
        EventStatus status,
        EventAudienceType audienceType,
        Set<java.util.UUID> courseIds,
        Set<java.util.UUID> batchIds,
        Set<java.util.UUID> individualIds
) {
}
