package com.nest.app.academy.dto;

import java.util.UUID;

public record FeaturedTrainerResponse(UUID id, UUID trainerMembershipId, String fullName, String profileImageUrl) {
}
