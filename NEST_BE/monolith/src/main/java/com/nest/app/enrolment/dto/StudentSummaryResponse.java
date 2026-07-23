package com.nest.app.enrolment.dto;

import java.util.UUID;

/** One row for a batch roster picker - just enough to show a human a name, not an ID. */
public record StudentSummaryResponse(
        UUID membershipId,
        UUID userId,
        String username,
        String fullName
) {
}
