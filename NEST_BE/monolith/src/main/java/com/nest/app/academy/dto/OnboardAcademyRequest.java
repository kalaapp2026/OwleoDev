package com.nest.app.academy.dto;

import com.nest.app.validation.Phone;
import com.nest.app.validation.StrictEmail;
import com.nest.app.validation.Username;
import com.nest.app.validation.PersonName;

import com.nest.app.academy.entity.AcademyCategory;
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
        @NotBlank @Phone String contactNumber,
        @StrictEmail String email,
        String plan,

        @NotBlank @Username String adminUsername,
        @NotBlank @PersonName String adminFullName,
        @NotBlank @Phone String adminPhone,
        @StrictEmail String adminEmail
) {
}
