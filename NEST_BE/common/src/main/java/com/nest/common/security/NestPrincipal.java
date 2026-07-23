package com.nest.common.security;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * The authenticated caller for the lifetime of one request: their identity plus every academy
 * membership their JWT carries, and which one is currently "active" (PRD Section 4.3 / 7.5).
 * Super Admin and Artist/Guest principals carry an empty membership list.
 */
public record NestPrincipal(
        UUID userId,
        String username,
        Role globalRole,
        List<MembershipClaim> memberships,
        UUID activeMembershipId
) {
    public Optional<MembershipClaim> activeMembership() {
        if (activeMembershipId == null) {
            return Optional.empty();
        }
        return memberships.stream().filter(m -> m.membershipId().equals(activeMembershipId)).findFirst();
    }

    public boolean hasMembership(UUID membershipId) {
        return memberships.stream().anyMatch(m -> m.membershipId().equals(membershipId));
    }

    public boolean hasFeature(String featureKey) {
        return activeMembership().map(m -> m.hasFeature(featureKey)).orElse(false);
    }

    public boolean hasCourse(UUID courseId) {
        return activeMembership().map(m -> m.hasCourse(courseId)).orElse(false);
    }

    public boolean isSuperAdmin() {
        return globalRole == Role.SUPER_ADMIN;
    }
}
