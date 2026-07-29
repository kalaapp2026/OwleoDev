package com.nest.common.security;

import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.UnauthorizedException;

import java.util.UUID;

/**
 * Request-scoped holder for the authenticated principal, populated by {@link JwtAuthFilter} and
 * cleared at the end of every request. Services call the static accessors below instead of
 * threading the principal through every method signature.
 *
 * <p>Every ERP-scoped repository query MUST filter by {@code currentAcademyId()} /
 * {@code currentMembershipId()} in addition to any Postgres RLS policy - RLS is defence in depth,
 * not the only line of defence (PRD Section 4.3).
 */
public final class TenantContext {

    private static final ThreadLocal<NestPrincipal> CURRENT = new ThreadLocal<>();

    private TenantContext() {
    }

    public static void set(NestPrincipal principal) {
        CURRENT.set(principal);
    }

    public static NestPrincipal get() {
        return CURRENT.get();
    }

    public static void clear() {
        CURRENT.remove();
    }

    public static NestPrincipal require() {
        NestPrincipal principal = CURRENT.get();
        if (principal == null) {
            throw new UnauthorizedException("No authenticated principal in context");
        }
        return principal;
    }

    public static UUID currentUserId() {
        return require().userId();
    }

    /** For callers that run on every request regardless of authentication (activity tracking) and
     * must treat "nobody logged in" as an ordinary case, not an error. */
    public static UUID currentUserIdOrNull() {
        NestPrincipal principal = CURRENT.get();
        return principal == null ? null : principal.userId();
    }

    public static MembershipClaim currentMembership() {
        return require().activeMembership()
                .orElseThrow(() -> new ForbiddenException("Request has no active academy membership"));
    }

    public static UUID currentMembershipId() {
        return currentMembership().membershipId();
    }

    public static UUID currentAcademyId() {
        return currentMembership().academyId();
    }

    public static boolean hasFeature(String featureKey) {
        return require().hasFeature(featureKey);
    }

    public static void assertFeature(String featureKey) {
        if (!hasFeature(featureKey)) {
            throw new ForbiddenException("Missing required feature grant: " + featureKey);
        }
    }

    public static void assertCourseAccess(UUID courseId) {
        if (!require().hasCourse(courseId)) {
            throw new ForbiddenException("Caller's course map does not include course " + courseId);
        }
    }
}
