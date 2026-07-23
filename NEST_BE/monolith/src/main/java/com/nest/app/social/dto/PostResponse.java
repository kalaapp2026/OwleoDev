package com.nest.app.social.dto;

import com.nest.app.social.entity.PostType;
import com.nest.app.social.entity.PostVisibility;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record PostResponse(
        UUID id, UUID authorMembershipId, UUID authorUserId, PostType type, String content,
        List<String> mediaUrls, PostVisibility visibility, UUID eventId, Instant createdAt
) {
}
