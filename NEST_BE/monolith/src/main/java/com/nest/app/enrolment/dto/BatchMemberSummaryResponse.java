package com.nest.app.enrolment.dto;

import java.util.UUID;

/** One roster row for the Attendance marking screen - a face and a name, not a bare membership
 * UUID. profileImageUrl is null when the student never uploaded a photo, in which case the UI
 * falls back to the first letter of fullName.
 *
 * <p>{@code courseId}/{@code courseName} say which of the batch's courses this student belongs to, so a
 * batch that spans Basic, Intermediate and Advanced can tag each name. Null only when the batch's
 * course could not be resolved. */
public record BatchMemberSummaryResponse(
        UUID membershipId,
        UUID userId,
        String username,
        String fullName,
        String profileImageUrl,
        UUID courseId,
        String courseName
) {
}
