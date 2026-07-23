package com.nest.app.academy.dto;

import jakarta.validation.constraints.NotBlank;

import java.util.Set;
import java.util.UUID;

public record AddHighlightRequest(@NotBlank String title, String description, Set<UUID> trainerMembershipIds) {
}
