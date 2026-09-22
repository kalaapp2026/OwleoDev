package com.nest.app.identity.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ResetPasswordRequest(
        @NotBlank String identifier,
        @NotBlank String code,
        @NotBlank @Size(min = 6, message = "Password must be at least 6 characters") String newPassword
) {
}
