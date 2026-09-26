package com.nest.app.enrolment.dto;

import java.time.LocalDate;
import java.util.UUID;

/** The public-safe subset of a trainer's profile - what the Academy Profile page's featured-
 * trainer drill-down shows to any member of the academy. Deliberately much thinner than
 * {@link TrainerDetailResponse}, which is PII-heavy (address, dob, salary via PersonDetails) and
 * gated to the registration/edit form - phone and email are included here because the reference
 * this screen is built from explicitly shows them as tap-to-call/tap-to-email for a trainer the
 * Admin has chosen to feature publicly. */
public record TrainerCardResponse(
        UUID membershipId,
        String fullName,
        String profileImageUrl,
        String qualification,
        String phone,
        String email,
        LocalDate joiningDate
) {
}
