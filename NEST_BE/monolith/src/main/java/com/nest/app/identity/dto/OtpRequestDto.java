package com.nest.app.identity.dto;

import com.nest.app.identity.entity.OtpPurpose;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/** identifier is username-or-phone, same resolution as /auth/identify - lets the "resend code"
 * link work regardless of which one the user originally typed. */
public record OtpRequestDto(
        @NotBlank String identifier,
        @NotNull OtpPurpose purpose
) {
}
