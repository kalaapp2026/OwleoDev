package com.nest.app.platform.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * @param deviceId client-generated and stored on the device. Deliberately NOT a hardware
 *                 identifier - it carries no PII and can't be correlated to anything outside NEST.
 */
public record DevicePingRequest(
        @NotBlank @Size(max = 128) String deviceId,
        @Size(max = 20) String platform,
        @Size(max = 40) String appVersion
) {}
