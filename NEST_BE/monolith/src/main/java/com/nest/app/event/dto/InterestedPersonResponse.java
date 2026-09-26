package com.nest.app.event.dto;

import java.util.UUID;

public record InterestedPersonResponse(UUID userId, String fullName, String profileImageUrl) {
}
