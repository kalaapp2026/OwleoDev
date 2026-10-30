package com.nest.app.dashboard.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.dashboard.dto.DashboardStatsResponse;
import com.nest.app.enrolment.entity.BatchStatus;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The Dashboard's stats row. Every count here reuses a repository method already exercised by the
 * Super Admin platform-metrics path, just scoped down to one academy instead of grouped across all
 * of them.
 */
@Service
public class DashboardService {

    private final CourseRepository courseRepository;
    private final BatchRepository batchRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final CourseMapRepository courseMapRepository;
    private final CourseFeatureGuard courseFeatureGuard;

    public DashboardService(CourseRepository courseRepository, BatchRepository batchRepository,
                             AcademyMembershipRepository membershipRepository,
                             CourseMapRepository courseMapRepository,
                             CourseFeatureGuard courseFeatureGuard) {
        this.courseRepository = courseRepository;
        this.batchRepository = batchRepository;
        this.membershipRepository = membershipRepository;
        this.courseMapRepository = courseMapRepository;
        this.courseFeatureGuard = courseFeatureGuard;
    }

    /** The whole academy's headcount. */
    public DashboardStatsResponse stats() {
        return stats(false);
    }

    /**
     * {@code mine} narrows every figure to the courses the caller holds any feature on, so a trainer
     * granted Attendance on Guitar sees Guitar's students, batches and trainers - not the academy's.
     * An admin has no restriction, so for them it is the same as the whole academy.
     */
    public DashboardStatsResponse stats(boolean mine) {
        Optional<Set<UUID>> scope = mine
                ? courseFeatureGuard.visibleCourseIdsAny(FeatureKey.ALL_DELEGABLE.toArray(String[]::new))
                : Optional.empty();
        return scope.map(this::scopedStats).orElseGet(this::academyStats);
    }

    private DashboardStatsResponse academyStats() {
        UUID academyId = TenantContext.currentAcademyId();

        int activeCourses = (int) courseRepository.countByAcademyIdAndStatus(academyId, CourseStatus.ACTIVE);

        // Batch has no academy_id of its own - same course-id detour BatchRepository's own doc
        // comments use for its per-academy counts.
        List<UUID> courseIds = courseRepository.findIdsByAcademyId(academyId);
        long activeBatches = courseIds.isEmpty() ? 0 : batchRepository.findByCourseIdIn(courseIds).stream()
                .filter(b -> b.getStatus() == BatchStatus.ACTIVE)
                .count();

        long totalStudents = membershipRepository
                .countByAcademyIdAndRoleTypeAndStatus(academyId, Role.STUDENT, MembershipStatus.ACTIVE);
        long totalTrainers = membershipRepository
                .countByAcademyIdAndRoleTypeAndStatus(academyId, Role.TRAINER, MembershipStatus.ACTIVE);

        return new DashboardStatsResponse(activeCourses, (int) activeBatches, (int) totalStudents, (int) totalTrainers);
    }

    private DashboardStatsResponse scopedStats(Set<UUID> grantedCourseIds) {
        if (grantedCourseIds.isEmpty()) {
            return new DashboardStatsResponse(0, 0, 0, 0);
        }
        UUID academyId = TenantContext.currentAcademyId();

        // Grants never cross academies, but the academy filter makes that a fact of this query
        // rather than an assumption about the data.
        List<Course> courses = courseRepository.findAllById(grantedCourseIds).stream()
                .filter(c -> academyId.equals(c.getAcademyId()) && c.getStatus() == CourseStatus.ACTIVE)
                .toList();
        List<UUID> courseIds = courses.stream().map(Course::getId).toList();
        if (courseIds.isEmpty()) {
            return new DashboardStatsResponse(0, 0, 0, 0);
        }

        // A trainer limited to some batches of a course counts only those.
        long activeBatches = batchRepository.findByCourseIdIn(courseIds).stream()
                .filter(b -> b.getStatus() == BatchStatus.ACTIVE)
                // Counted once, through any of its courses the person holds that has it in scope.
                .filter(b -> b.allCourseIds().stream().filter(courseIds::contains)
                        .anyMatch(c -> CourseFeatureGuard.inScope(courseFeatureGuard.batchScope(c), b.getId())))
                .count();

        Set<UUID> memberIds = courseMapRepository.findByCourseIdIn(courseIds).stream()
                .filter(CourseMap::isActive)
                .map(CourseMap::getMembershipId)
                .collect(Collectors.toSet());
        List<AcademyMembership> members = membershipRepository.findAllById(memberIds).stream()
                .filter(m -> academyId.equals(m.getAcademyId()) && m.getStatus() == MembershipStatus.ACTIVE)
                .toList();
        long students = members.stream().filter(m -> m.getRoleType() == Role.STUDENT).count();
        long trainers = members.stream().filter(m -> m.getRoleType() == Role.TRAINER).count();

        return new DashboardStatsResponse(courseIds.size(), (int) activeBatches, (int) students, (int) trainers);
    }
}
