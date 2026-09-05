package com.nest.app.identity.service;

import com.nest.app.identity.repository.CourseFeatureGrantRepository;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Phase 2 of per-course RBAC: fine-grained enforcement that the coarse {@code @RequiresFeature}
 * gate can't do. The annotation checks the UNION ("has this feature on any course?"); this checks
 * the SPECIFIC course ("has Attendance on <i>this</i> course?"), so a trainer granted Attendance on
 * Guitar genuinely cannot mark Dance attendance.
 *
 * <p>Called from inside course-scoped service actions, where the target course is known. Admins and
 * Super Admins bypass it (full access by role, exactly like the annotation aspect) - it only gates
 * Trainers, whose access lives in {@code course_feature_grants}.
 */
@Component
public class CourseFeatureGuard {

    private final CourseFeatureGrantRepository courseFeatureGrantRepository;

    public CourseFeatureGuard(CourseFeatureGrantRepository courseFeatureGrantRepository) {
        this.courseFeatureGrantRepository = courseFeatureGrantRepository;
    }

    public void assertCourseFeature(UUID courseId, String featureKey) {
        if (!hasCourseFeature(courseId, featureKey)) {
            throw new ForbiddenException(
                    "You don't have the '" + featureKey + "' permission for this course");
        }
    }

    /**
     * The same check as {@link #assertCourseFeature}, as a question rather than an assertion.
     *
     * <p>For deciding what to include in a response - a student's fee profile lists only the
     * courses the caller may see. Filtering a list by catching the assert's exception per element
     * would be both slower and a lie about what exceptions are for.</p>
     */
    public boolean hasCourseFeature(UUID courseId, String featureKey) {
        NestPrincipal principal = TenantContext.require();
        if (principal.isSuperAdmin()) {
            return true;
        }
        MembershipClaim membership = principal.activeMembership()
                .orElseThrow(() -> new ForbiddenException("Request has no active academy membership"));
        if (membership.roleType() == Role.ACADEMY_ADMIN) {
            return true;
        }
        return courseFeatureGrantRepository
                .existsByMembershipIdAndCourseIdAndFeatureKey(membership.membershipId(), courseId, featureKey);
    }

    /**
     * Which courses the caller may see for {@code featureKey}, or empty for "no restriction".
     *
     * <p>The list-endpoint counterpart to {@link #hasCourseFeature}. That method answers "may I
     * touch this one course?", which protects writes; this answers "which courses belong on my
     * screen at all?", which is what stops a Trainer granted Attendance on Guitar from seeing
     * every other course's classes listed in front of them.
     *
     * <p>Returns {@link Optional#empty()} rather than the full academy list for Admins and Super
     * Admins deliberately: the caller then skips filtering entirely instead of building and
     * intersecting a set that was never going to exclude anything.
     */
    public java.util.Optional<java.util.Set<UUID>> visibleCourseIds(String featureKey) {
        NestPrincipal principal = TenantContext.require();
        if (principal.isSuperAdmin()) {
            return java.util.Optional.empty();
        }
        MembershipClaim membership = principal.activeMembership()
                .orElseThrow(() -> new ForbiddenException("Request has no active academy membership"));
        if (membership.roleType() == Role.ACADEMY_ADMIN) {
            return java.util.Optional.empty();
        }

        // A Trainer with no grant for this feature gets an empty set, not "everything" - the
        // difference between an empty screen and a full one they shouldn't be looking at.
        return java.util.Optional.of(
                courseFeatureGrantRepository.findByMembershipId(membership.membershipId()).stream()
                        .filter(g -> g.getFeatureKey().equals(featureKey))
                        .map(g -> g.getCourseId())
                        .collect(java.util.stream.Collectors.toSet()));
    }
}
