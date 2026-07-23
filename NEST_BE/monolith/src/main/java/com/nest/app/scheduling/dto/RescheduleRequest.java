package com.nest.app.scheduling.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;
import java.time.LocalTime;

public record RescheduleRequest(
        @NotNull LocalDate newDate,
        @NotNull LocalTime newStartTime,
        @NotNull LocalTime newEndTime,
        @NotBlank String reason
) {
}
