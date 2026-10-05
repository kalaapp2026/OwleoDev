package com.nest.app.profile.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;
import java.util.UUID;

public record AchievementRequest(
        @NotBlank String title,
        String description,
        @NotBlank String type,
        @NotNull LocalDate date,
        UUID academyId
) {
}
