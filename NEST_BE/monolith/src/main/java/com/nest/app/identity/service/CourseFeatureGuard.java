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
    private final com.nest.app.identity.repository.TrainerCourseBatchRepository trainerCourseBatchRepository;

    public CourseFeatureGuard(CourseFeatureGrantRepository courseFeatureGrantRepository,
                              com.nest.app.identity.repository.TrainerCourseBatchRepository trainerCourseBatchRepository) {
        this.courseFeatureGrantRepository = courseFeatureGrantRepository;
        this.trainerCourseBatchRepository = trainerCourseBatchRepository;
    }

    /**
     * Which batches of {@code courseId} the caller was limited to (the "Batches in scope" picked when a
     * trainer is set up), or empty for "no limit" - admins, and a trainer given the whole course.
     *
     * <p>A course permission says WHICH COURSE; this says which batches within it. They are separate
     * on purpose: a trainer with Attendance on Guitar who was given only Batch A should not see or mark
     * Batch B. Callers must apply it wherever a batch's classes, students or records are shown or
     * changed - the permission check alone lets a scoped trainer into every batch of the course.
     */
    public java.util.Optional<java.util.Set<UUID>> batchScope(UUID courseId) {
        NestPrincipal principal = TenantContext.require();
        if (principal.isSuperAdmin()) {
            return java.util.Optional.empty();
        }
        MembershipClaim membership = principal.activeMembership()
                .orElseThrow(() -> new ForbiddenException("Request has no active academy membership"));
        if (membership.roleType() == Role.ACADEMY_ADMIN) {
            return java.util.Optional.empty();
        }
        var rows = trainerCourseBatchRepository.findByMembershipIdAndCourseId(membership.membershipId(), courseId);
        if (rows.isEmpty()) {
            return java.util.Optional.empty();
        }
        return java.util.Optional.of(rows.stream()
                .map(com.nest.app.identity.entity.TrainerCourseBatch::getBatchId)
                .collect(java.util.stream.Collectors.toSet()));
    }

    /** True when {@code batchId} is inside [scope] - an absent scope ("no limit") includes everything. */
    public static boolean inScope(java.util.Optional<java.util.Set<UUID>> scope, UUID batchId) {
        return scope.isEmpty() || scope.get().contains(batchId);
    }

    public void assertBatchInScope(UUID courseId, UUID batchId) {
        if (!inScope(batchScope(courseId), batchId)) {
            throw new ForbiddenException("That batch is outside the batches you were given for this course");
        }
    }

    public void assertCourseFeature(UUID courseId, String featureKey) {
        if (!hasCourseFeature(courseId, featureKey)) {
            throw new ForbiddenException(
                    "You don't have the '" + featureKey + "' permission for this course");
        }
    }

    /**
     * For something several features legitimately need - the list of a course's students is needed
     * by whoever registers students and whoever builds batches. Passing holds ANY of
     * {@code featureKeys} on this course. The write that follows still checks its own, narrower
     * permission; this only decides who may look.
     */
    public void assertAnyCourseFeature(UUID courseId, String... featureKeys) {
        for (String key : featureKeys) {
            if (hasCourseFeature(courseId, key)) {
                return;
            }
        }
        throw new ForbiddenException("You don't have the '" + String.join("' or '", featureKeys)
                + "' permission for this course");
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
        return visibleCourseIdsAny(featureKey);
    }

    /**
     * The courses on which the caller holds AT LEAST ONE of {@code featureKeys}, or empty for "no
     * restriction". The union counterpart to {@link #assertAnyCourseFeature}: a screen that several
     * permissions open (the Schedule screen is reached by Batch scheduling or Reschedule alike)
     * must list the courses of whichever one the person has, not just the first it thought of.
     */
    public java.util.Optional<java.util.Set<UUID>> visibleCourseIdsAny(String... featureKeys) {
        java.util.Set<String> wanted = java.util.Set.of(featureKeys);
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
                        .filter(g -> wanted.contains(g.getFeatureKey()))
                        .map(g -> g.getCourseId())
                        .collect(java.util.stream.Collectors.toSet()));
    }
}
