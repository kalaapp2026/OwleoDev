package com.nest.app.academy.dto;

import jakarta.validation.constraints.NotNull;

import java.util.UUID;

public record AddFeaturedTrainerRequest(@NotNull UUID trainerMembershipId) {
}
