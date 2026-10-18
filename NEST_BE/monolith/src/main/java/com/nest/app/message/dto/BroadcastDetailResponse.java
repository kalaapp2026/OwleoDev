package com.nest.app.message.dto;

import com.nest.common.security.Role;

import java.util.List;
import java.util.UUID;

/** One broadcast with who received it and who has opened it. {@code recipients} is empty for a
 * broadcast sent before read tracking existed - there is no per-person record to show. */
public record BroadcastDetailResponse(BroadcastResponse broadcast, List<Recipient> recipients) {

    public record Recipient(UUID membershipId, String name, Role roleType, boolean read) {
    }
}
