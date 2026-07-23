package com.nest.identity.dto;

import com.nest.identity.entity.OtpPurpose;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record OtpRequestDto(
        @NotBlank String phone,
        @NotNull OtpPurpose purpose
) {
}
