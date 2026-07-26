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
        NestPrincipal principal = TenantContext.require();
        if (principal.isSuperAdmin()) {
            return;
        }
        MembershipClaim membership = principal.activeMembership()
                .orElseThrow(() -> new ForbiddenException("Request has no active academy membership"));
        if (membership.roleType() == Role.ACADEMY_ADMIN) {
            return;
        }
        boolean granted = courseFeatureGrantRepository
                .existsByMembershipIdAndCourseIdAndFeatureKey(membership.membershipId(), courseId, featureKey);
        if (!granted) {
            throw new ForbiddenException(
                    "You don't have the '" + featureKey + "' permission for this course");
        }
    }
}
