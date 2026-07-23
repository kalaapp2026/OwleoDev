package com.nest.app.identity.dto;

import com.nest.common.security.Role;

import java.util.Set;
import java.util.UUID;

public record MembershipSummary(
        UUID membershipId,
        UUID academyId,
        String academyName,
        Role roleType,
        String status,
        Set<String> features,
        Set<UUID> courseIds
) {
}
