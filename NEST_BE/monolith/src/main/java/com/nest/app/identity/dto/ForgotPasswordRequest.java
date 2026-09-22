package com.nest.app.identity.dto;

import jakarta.validation.constraints.NotBlank;

/** Same identifier shape as {@link IdentifyRequest} (username or email) - the account's own email
 * on file is where the reset code actually goes, not necessarily what the caller typed. */
public record ForgotPasswordRequest(@NotBlank String identifier) {
}
