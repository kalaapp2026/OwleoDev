package com.nest.app.enrolment.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

import java.util.Set;
import java.util.UUID;

public record RegisterTrainerRequest(
        @NotBlank String username,
        @NotBlank String fullName,
        @NotBlank String phone,
        @Email String email,
        @NotEmpty Set<String> features,
        @NotEmpty Set<UUID> courseIds
) {
}
