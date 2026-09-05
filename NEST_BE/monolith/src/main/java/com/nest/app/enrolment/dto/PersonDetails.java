package com.nest.app.enrolment.dto;

import java.time.LocalDate;

/**
 * The profile fields shared by student and trainer registration.
 *
 * <p>Grouped into one record rather than repeated across both requests: they are genuinely the
 * same fields asked in the same order by the same form, and duplicating a dozen parameters twice
 * is how the two drift apart.
 *
 * <p>Every field is optional. The form marks several as required, but that is a form rule about
 * completeness, not a data rule - a walk-in registration taken over a counter often has a name
 * and a phone number and nothing else yet, and rejecting it would push staff back to paper.
 */
public record PersonDetails(
        String firstName,
        String lastName,
        String gender,
        String bloodGroup,
        String altPhone,
        String photoUrl,

        // Structured address. addressLine1 maps onto the existing single-line `address` column.
        String addressLine1,
        String addressLine2,
        String landmark,
        String city,
        String district,
        String state,
        String country,
        String pinCode,

        /** Student-only. */
        String guardianName,
        String emergencyContact,

        /** Trainer-only. */
        String qualification,

        /** Trainer-only. Monthly pay at this academy; null means not recorded, which is not zero. */
        java.math.BigDecimal salary,

        /** The date this person joins this academy. Defaults to today when absent. */
        LocalDate joiningDate
) {
}
