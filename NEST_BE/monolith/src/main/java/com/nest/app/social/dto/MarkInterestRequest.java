package com.nest.app.social.dto;

import java.util.UUID;

/** Exactly one of eventId/postId must be set (validated in service - a plain bean constraint
 * can't express "exactly one of these two"). */
public record MarkInterestRequest(UUID eventId, UUID postId) {
}
