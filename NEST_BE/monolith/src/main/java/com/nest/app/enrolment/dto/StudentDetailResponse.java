package com.nest.app.enrolment.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Map;
import java.util.UUID;

/** Everything the student edit form needs to pre-fill: profile + the current per-course agreed fees. */
public record StudentDetailResponse(
        UUID userId,
        UUID membershipId,
        String username,
        String fullName,
        String phone,
        String email,
        LocalDate dob,
        String address,
        String city,
        String state,
        Map<UUID, BigDecimal> courseFees,

        /** The V26/V27 profile fields, so an edit round-trips without losing them. */
        PersonDetails details
) {
}
