package com.nest.app.dashboard.service;

import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.dashboard.dto.DashboardStatsResponse;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchStatus;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DashboardServiceTest {

    @Mock
    private CourseRepository courseRepository;
    @Mock
    private BatchRepository batchRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;

    private DashboardService dashboardService;

    private final UUID academyId = UUID.randomUUID();
    private final UUID courseId1 = UUID.randomUUID();
    private final UUID courseId2 = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        dashboardService = new DashboardService(courseRepository, batchRepository, membershipRepository);

        UUID adminMembershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(adminMembershipId, academyId, "Kalakshetra",
                Role.ACADEMY_ADMIN, Set.of(), Set.of(courseId1, courseId2));
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN,
                List.of(claim), adminMembershipId));
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    @Test
    void countsOnlyActiveBatchesAndScopesEverythingToTheCurrentAcademy() {
        when(courseRepository.countByAcademyIdAndStatus(academyId, CourseStatus.ACTIVE)).thenReturn(2L);
        when(courseRepository.findIdsByAcademyId(academyId)).thenReturn(List.of(courseId1, courseId2));
        when(batchRepository.findByCourseIdIn(List.of(courseId1, courseId2))).thenReturn(List.of(
                Batch.builder().id(UUID.randomUUID()).courseId(courseId1).name("Batch A").status(BatchStatus.ACTIVE).build(),
                Batch.builder().id(UUID.randomUUID()).courseId(courseId1).name("Batch B").status(BatchStatus.INACTIVE).build(),
                Batch.builder().id(UUID.randomUUID()).courseId(courseId2).name("Batch A").status(BatchStatus.ACTIVE).build()
        ));
        when(membershipRepository.countByAcademyIdAndRoleTypeAndStatus(academyId, Role.STUDENT, MembershipStatus.ACTIVE))
                .thenReturn(24L);
        when(membershipRepository.countByAcademyIdAndRoleTypeAndStatus(academyId, Role.TRAINER, MembershipStatus.ACTIVE))
                .thenReturn(3L);

        DashboardStatsResponse result = dashboardService.stats();

        assertThat(result).isEqualTo(new DashboardStatsResponse(2, 2, 24, 3));
    }

    @Test
    void anAcademyWithNoCoursesYetHasZeroBatchesWithoutQueryingForThem() {
        when(courseRepository.countByAcademyIdAndStatus(academyId, CourseStatus.ACTIVE)).thenReturn(0L);
        when(courseRepository.findIdsByAcademyId(academyId)).thenReturn(List.of());
        when(membershipRepository.countByAcademyIdAndRoleTypeAndStatus(eq(academyId), eq(Role.STUDENT), eq(MembershipStatus.ACTIVE)))
                .thenReturn(0L);
        when(membershipRepository.countByAcademyIdAndRoleTypeAndStatus(eq(academyId), eq(Role.TRAINER), eq(MembershipStatus.ACTIVE)))
                .thenReturn(0L);

        DashboardStatsResponse result = dashboardService.stats();

        assertThat(result).isEqualTo(new DashboardStatsResponse(0, 0, 0, 0));
    }
}
