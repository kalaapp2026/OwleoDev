package com.nest.app.identity.dto;

import com.nest.app.validation.StrongPassword;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ResetPasswordRequest(
        @NotBlank String identifier,
        @NotBlank String code,
        @NotBlank @StrongPassword String newPassword
) {
}
