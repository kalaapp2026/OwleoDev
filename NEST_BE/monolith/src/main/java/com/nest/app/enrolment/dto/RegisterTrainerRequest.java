package com.nest.app.enrolment.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Past;

import java.time.LocalDate;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * {@code courseFeatures} maps each course the trainer is assigned to -&gt; the features granted on
 * that course. The "same features for all courses" toggle in the UI just fills every course's set
 * with the same values before sending; "per-course" sends each course its own set. A course with
 * an empty set means "assigned to the course, no features yet". Cascading delegation still applies:
 * every feature across every course must be one the creator themselves holds (PRD 3.5).
 */
public record RegisterTrainerRequest(
        @NotBlank String username,
        @NotBlank String fullName,
        @NotBlank String phone,
        @Email @NotBlank String email,
        @Past @NotNull LocalDate dob,
        String address,
        String city,
        String state,
        Integer yearsOfExperience,
        @NotEmpty Map<UUID, Set<String>> courseFeatures,
        /** Per course, which batches the grants above apply to. An absent or empty set means
         * every batch on that course - the access a trainer had before batches could be named. */
        Map<UUID, Set<UUID>> courseBatches,
        PersonDetails details
) {
}
