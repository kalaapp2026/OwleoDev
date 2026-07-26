package com.nest.app.identity.dto;

import com.nest.app.identity.entity.ArtistApplicationStatus;

import java.time.Instant;
import java.util.UUID;

public record ArtistApplicationResponse(
        UUID id,
        UUID userId,
        String username,
        String fullName,
        ArtistApplicationStatus status,
        Instant createdAt
) {
}
