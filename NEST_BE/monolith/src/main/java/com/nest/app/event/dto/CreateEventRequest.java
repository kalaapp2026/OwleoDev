package com.nest.app.event.dto;

import com.nest.app.event.entity.EventType;
import com.nest.app.event.entity.EventVisibility;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDateTime;

public record CreateEventRequest(
        @NotNull EventType type,
        @NotBlank String title,
        String description,
        @NotNull LocalDateTime eventDate,
        String location,
        @NotNull EventVisibility visibility,
        String coverImageUrl
) {
}
