package com.nest.app.enrolment.dto;

import java.util.UUID;

/** One row for a batch roster picker - just enough to show a human a name, not an ID. {@code active}
 * is this student's per-course enrolment state (see CourseMap.active) - the management roster shows
 * inactive ones too so they can be reactivated; the batch picker asks for active-only. */
public record StudentSummaryResponse(
        UUID membershipId,
        UUID userId,
        String username,
        String fullName,
        boolean active
) {
}
