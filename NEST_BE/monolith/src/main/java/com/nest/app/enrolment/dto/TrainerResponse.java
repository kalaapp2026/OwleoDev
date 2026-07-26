package com.nest.app.enrolment.dto;

import java.util.Map;
import java.util.Set;
import java.util.UUID;

public record TrainerResponse(
        UUID userId,
        UUID membershipId,
        String username,
        String temporaryPassword,
        /** courseId -> features granted on that course (the per-course checklist that was saved). */
        Map<UUID, Set<String>> courseFeatures
) {
}
