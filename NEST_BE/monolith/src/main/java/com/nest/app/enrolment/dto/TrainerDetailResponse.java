package com.nest.app.enrolment.dto;

import java.time.LocalDate;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/** Everything the trainer edit form needs to pre-fill: profile + the current per-course features. */
public record TrainerDetailResponse(
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
        Integer yearsOfExperience,
        Map<UUID, Set<String>> courseFeatures,

        /** The V26/V27 profile fields, so an edit round-trips without losing them. */
        PersonDetails details,

        /** Per course, the batches this trainer is scoped to. An absent course means every batch. */
        Map<UUID, Set<UUID>> courseBatches
) {
}
