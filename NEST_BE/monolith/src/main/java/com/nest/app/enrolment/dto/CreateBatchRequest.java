package com.nest.app.enrolment.dto;

import com.nest.app.enrolment.entity.BatchType;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.util.UUID;

public record CreateBatchRequest(
        @NotNull UUID courseId,
        @NotBlank String name,
        String description,
        @NotNull BatchType batchType,
        UUID trainerMembershipId
) {
}
