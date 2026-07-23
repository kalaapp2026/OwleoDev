package com.nest.app.enrolment.dto;

import java.util.UUID;

/** One row for a batch's default-trainer picker - just enough to show a human a name, not an ID. */
public record TrainerSummaryResponse(
        UUID membershipId,
        UUID userId,
        String username,
        String fullName
) {
}
