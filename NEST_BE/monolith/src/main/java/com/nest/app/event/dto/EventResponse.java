package com.nest.app.event.dto;

import com.nest.app.event.entity.EventType;
import com.nest.app.event.entity.EventVisibility;

import java.time.LocalDateTime;
import java.util.UUID;

public record EventResponse(
        UUID id, UUID academyId, EventType type, String title, String description,
        LocalDateTime eventDate, String location, EventVisibility visibility, String coverImageUrl
) {
}
