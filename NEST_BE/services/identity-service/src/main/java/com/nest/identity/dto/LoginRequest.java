package com.nest.identity.dto;

import jakarta.validation.constraints.NotBlank;

/** Password login - only Admin/Trainer/Super Admin accounts have a password (PRD 3.2/3.5). */
public record LoginRequest(
        @NotBlank String username,
        @NotBlank String password
) {
}
