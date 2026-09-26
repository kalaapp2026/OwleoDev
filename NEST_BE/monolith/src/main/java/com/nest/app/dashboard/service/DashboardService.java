package com.nest.app.dashboard.service;

import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.dashboard.dto.DashboardStatsResponse;
import com.nest.app.enrolment.entity.BatchStatus;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.UUID;

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

    public DashboardService(CourseRepository courseRepository, BatchRepository batchRepository,
                             AcademyMembershipRepository membershipRepository) {
        this.courseRepository = courseRepository;
        this.batchRepository = batchRepository;
        this.membershipRepository = membershipRepository;
    }

    public DashboardStatsResponse stats() {
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
}
