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

/** Trainer edit. Username is immutable (it's the login id) so it isn't here. {@code courseFeatures}
 * fully replaces the trainer's course assignment + per-course feature checklist, same shape and
 * cascading-delegation cap as registration. */
public record UpdateTrainerRequest(
        @NotBlank String fullName,
        @NotBlank String phone,
        @Email @NotBlank String email,
        @Past @NotNull LocalDate dob,
        String address,
        String city,
        String state,
        Integer yearsOfExperience,
        @NotEmpty Map<UUID, Set<String>> courseFeatures,

        /** Per course, which batches the grants apply to. Empty for a course means every batch. */
        Map<UUID, Set<UUID>> courseBatches,

        /** The extended profile fields. Null leaves every one of them as it was. */
        PersonDetails details
) {
}
