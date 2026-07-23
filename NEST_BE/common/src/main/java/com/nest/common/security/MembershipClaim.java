package com.nest.common.security;

import java.util.Set;
import java.util.UUID;

/**
 * One academy_memberships row, as carried inside the JWT. A user's token carries a LIST of these
 * (PRD Section 4.3) since a Student may hold more than one active membership.
 */
public record MembershipClaim(
        UUID membershipId,
        UUID academyId,
        String academyName,
        Role roleType,
        Set<String> features,
        Set<UUID> courseIds
) {
    public boolean hasFeature(String featureKey) {
        return features != null && features.contains(featureKey);
    }

    public boolean hasCourse(UUID courseId) {
        return courseIds != null && courseIds.contains(courseId);
    }
}
