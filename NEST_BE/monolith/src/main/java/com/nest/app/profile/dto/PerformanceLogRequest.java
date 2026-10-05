package com.nest.app.profile.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;
import java.util.UUID;

public record PerformanceLogRequest(
        @NotBlank String title,
        @NotBlank String category,
        @NotBlank String result,
        @NotNull LocalDate date,
        UUID academyId,
        String notes
) {
}
