package com.nest.app.scheduling.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.UUID;

/** Assigns a substitute for one session only. */
public record SwapInstructorRequest(
        @NotNull UUID substituteMembershipId,
        /** Optional - a substitution is self-explanatory far more often than a cancellation is. */
        @Size(max = 300) String reason
) {
}
