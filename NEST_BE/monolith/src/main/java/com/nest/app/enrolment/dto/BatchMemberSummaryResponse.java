package com.nest.app.enrolment.dto;

import java.util.UUID;

/** One roster row for the Attendance marking screen - a face and a name, not a bare membership
 * UUID. profileImageUrl is null when the student never uploaded a photo, in which case the UI
 * falls back to the first letter of fullName. */
public record BatchMemberSummaryResponse(
        UUID membershipId,
        UUID userId,
        String username,
        String fullName,
        String profileImageUrl
) {
}
