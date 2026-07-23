package com.nest.identity.dto;

import java.util.UUID;

/**
 * temporaryPassword is returned here so the caller (academy-service) can relay it via
 * email/SMS (PRD 3.2). Once notification-service exists (Phase 4) this should move to a
 * credentials.issued Kafka event instead of a synchronous response field.
 */
public record ProvisionAcademyAdminResponse(
        UUID userId,
        UUID membershipId,
        String username,
        String temporaryPassword
) {
}
