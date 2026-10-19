package com.nest.app.identity.dto;

import jakarta.validation.constraints.NotBlank;

/** Step one of changing a password: "is this really your current password?" */
public record VerifyPasswordRequest(@NotBlank String currentPassword) {
}
