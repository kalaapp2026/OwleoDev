package com.nest.app.event.dto;

import com.nest.app.event.entity.EventAudienceType;
import com.nest.app.event.entity.EventStatus;
import com.nest.app.event.entity.EventType;
import com.nest.app.event.entity.EventVisibility;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Set;
import java.util.UUID;

public record EventResponse(
        UUID id, UUID academyId, EventType type, String title, String description,
        LocalDateTime eventDate, LocalDateTime endDate, String location, String venueMapsUrl,
        EventVisibility visibility, String coverImageUrl, LocalDate interestDeadline,
        EventStatus status, EventAudienceType audienceType,
        Set<UUID> courseIds, Set<UUID> batchIds, Set<UUID> individualIds,
        /** Computed from real roster data for the current audienceType, never stored. */
        int invitedCount,
        /** Computed from the Interest table, never stored. */
        int interestedCount
) {
}
