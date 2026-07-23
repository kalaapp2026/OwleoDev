package com.nest.app.social.dto;

import com.nest.app.social.entity.PostType;
import com.nest.app.social.entity.PostVisibility;
import jakarta.validation.constraints.NotNull;

import java.util.List;
import java.util.UUID;

public record CreatePostRequest(
        @NotNull PostType type,
        String content,
        List<String> mediaUrls,
        @NotNull PostVisibility visibility,
        UUID eventId
) {
}
