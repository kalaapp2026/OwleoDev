package com.nest.app.identity.dto;

import com.nest.app.identity.entity.OtpPurpose;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

public record OtpVerifyRequest(
        @NotBlank String identifier,
        @NotBlank @Pattern(regexp = "\\d{4,8}") String code,
        @NotNull OtpPurpose purpose
) {
}
