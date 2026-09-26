package com.nest.app.event.dto;

import com.nest.app.event.entity.EventStatus;
import jakarta.validation.constraints.NotNull;

public record EventStatusUpdateRequest(@NotNull EventStatus status) {
}
