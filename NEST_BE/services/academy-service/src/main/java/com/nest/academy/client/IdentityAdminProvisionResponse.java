package com.nest.academy.client;

import java.util.UUID;

public record IdentityAdminProvisionResponse(
        UUID userId,
        UUID membershipId,
        String username,
        String temporaryPassword
) {
}
