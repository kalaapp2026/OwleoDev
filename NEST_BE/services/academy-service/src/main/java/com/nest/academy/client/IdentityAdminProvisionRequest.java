package com.nest.academy.client;

import java.util.UUID;

/** Mirrors identity-service's ProvisionAcademyAdminRequest - each service owns its own contract
 * DTOs for cross-service calls rather than sharing entity/DTO classes (database-per-service). */
public record IdentityAdminProvisionRequest(
        String username,
        String fullName,
        String phone,
        String email,
        UUID academyId,
        String academyName
) {
}
