package com.nest.app.identity.dto;

import jakarta.validation.constraints.NotBlank;

/** Single field, username or phone - the whole point of the unified login flow. */
public record IdentifyRequest(@NotBlank String identifier) {
}
