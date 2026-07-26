package com.nest.app.identity.dto;

import java.util.UUID;

/** One row in a people-search result - just enough to show a face and a name, never PII like
 * phone/email (search is reachable by anyone logged in, unlike a profile the person owns). */
public record UserSearchResult(
        UUID id,
        String username,
        String fullName,
        String profileImageUrl
) {
}
