package com.nest.app.scheduling.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** Why a session isn't happening. Required, not optional - "cancelled" with no explanation is
 * exactly what makes a student turn up anyway. */
public record CancelClassRequest(
        @NotBlank @Size(max = 300) String reason
) {
}
