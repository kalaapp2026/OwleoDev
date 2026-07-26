package com.nest.app.enrolment.dto;

import java.util.UUID;

/** One row for a batch's default-trainer picker - just enough to show a human a name, not an ID.
 * {@code active} is this trainer's per-course mapping state (CourseMap.active); Academy Admins,
 * who are pulled in regardless of course mapping, are always reported active. */
public record TrainerSummaryResponse(
        UUID membershipId,
        UUID userId,
        String username,
        String fullName,
        boolean active
) {
}
