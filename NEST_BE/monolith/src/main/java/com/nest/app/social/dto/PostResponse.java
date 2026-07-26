package com.nest.app.social.dto;

import com.nest.app.social.entity.PostType;
import com.nest.app.social.entity.PostVisibility;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** {@code authorDisplayName}/{@code authorAvatarUrl} are resolved server-side so the feed always
 * has someone to show: the Academy's name/logo for a membership-authored post (Admin/Trainer),
 * or the person's own name/photo for an Artist/Super Admin's personal post. */
public record PostResponse(
        UUID id, UUID authorMembershipId, UUID authorUserId, PostType type, String content,
        List<String> mediaUrls, PostVisibility visibility, UUID eventId, Instant createdAt,
        String authorDisplayName, String authorAvatarUrl
) {
}
