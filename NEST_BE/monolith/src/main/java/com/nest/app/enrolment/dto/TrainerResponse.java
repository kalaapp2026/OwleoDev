package com.nest.app.enrolment.dto;

import java.util.Set;
import java.util.UUID;

public record TrainerResponse(
        UUID userId,
        UUID membershipId,
        String username,
        String temporaryPassword,
        Set<String> features,
        Set<UUID> courseIds
) {
}
