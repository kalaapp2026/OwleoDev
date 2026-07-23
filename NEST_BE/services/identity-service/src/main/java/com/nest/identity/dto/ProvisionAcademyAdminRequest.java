package com.nest.identity.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.util.UUID;

/**
 * Called by academy-service during Super Admin onboarding (PRD 3.2) to provision the academy's
 * first Academy Admin login. Internal, service-to-service only - see InternalApiKeyFilter.
 */
public record ProvisionAcademyAdminRequest(
        @NotBlank String username,
        @NotBlank String fullName,
        @NotBlank String phone,
        @Email String email,
        @NotNull UUID academyId,
        @NotBlank String academyName
) {
}
