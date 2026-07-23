package com.nest.app.academy.dto;

import com.nest.app.academy.entity.AcademyCategory;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/** Super Admin onboarding form (PRD 3.2) - academy profile plus the first Academy Admin's details. */
public record OnboardAcademyRequest(
        @NotBlank String academyName,
        @NotNull AcademyCategory category,
        String logoUrl,
        @NotBlank String address,
        @NotBlank String city,
        @NotBlank String state,
        @NotBlank String contactNumber,
        @Email String email,
        String plan,

        @NotBlank String adminUsername,
        @NotBlank String adminFullName,
        @NotBlank String adminPhone,
        @Email String adminEmail
) {
}
