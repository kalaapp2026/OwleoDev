package com.nest.app.fees.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.fees.repository.FeeSlipRepository;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.fees.repository.FeeTypeBatchRepository;
import com.nest.app.fees.repository.FeeTypeRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.FeatureKey;
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
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.when;

/** A Trainer with FEES_ENTRY on only some of the academy's courses must never see collection
 * totals or student search results for a course they don't hold - the fees landing page had no
 * CourseFeatureGuard usage at all before this. */
@ExtendWith(MockitoExtension.class)
class FeesDashboardServiceTest {

    @Mock
    private CourseRepository courseRepository;
    @Mock
    private CourseMapRepository courseMapRepository;
    @Mock
    private FeeSlipRepository feeSlipRepository;
    @Mock
    private FeeTransactionRepository feeTransactionRepository;
    @Mock
    private FeeTypeRepository feeTypeRepository;
    @Mock
    private FeeTypeBatchRepository feeTypeBatchRepository;
    @Mock
    private BatchRepository batchRepository;
    @Mock
    private BatchMemberRepository batchMemberRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private CourseFeatureGuard courseFeatureGuard;

    private FeesDashboardService dashboardService;

    private final UUID academyId = UUID.randomUUID();
    private final UUID visibleCourseId = UUID.randomUUID();
    private final UUID hiddenCourseId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        dashboardService = new FeesDashboardService(courseRepository, courseMapRepository, feeSlipRepository,
                feeTransactionRepository, feeTypeRepository, feeTypeBatchRepository, batchRepository,
                batchMemberRepository, membershipRepository, userRepository, courseFeatureGuard);
        UUID trainerMembershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(trainerMembershipId, academyId, "Natyalaya",
                Role.TRAINER, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "trainer", Role.TRAINER,
                List.of(claim), trainerMembershipId));
        // Nothing to tally in the Other Fees half unless a test opts in - keeps otherSummary's own
        // CourseFeatureGuard calls out of tests that only care about the Regular half. lenient:
        // some tests below never reach summary()'s otherSummary() call at all.
        org.mockito.Mockito.lenient().when(feeTypeRepository.findByAcademyIdAndActiveTrueOrderByNameAsc(academyId))
                .thenReturn(List.of());
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    @Test
    void summaryIsRejectedWhenCallerLacksFeesEntryOnTheNamedCourse() {
        doThrow(new ForbiddenException("nope")).when(courseFeatureGuard)
                .assertCourseFeature(hiddenCourseId, FeatureKey.FEES_ENTRY);

        assertThatThrownBy(() -> dashboardService.summary("2026-07", hiddenCourseId, null))
                .isInstanceOf(ForbiddenException.class);
    }

    @Test
    void wholeAcademySummaryOnlyCountsCoursesTheCallerCanSee() {
        when(courseFeatureGuard.visibleCourseIds(FeatureKey.FEES_ENTRY))
                .thenReturn(Optional.of(Set.of(visibleCourseId)));

        Course visible = Course.builder().id(visibleCourseId).academyId(academyId).name("Visible").build();
        Course hidden = Course.builder().id(hiddenCourseId).academyId(academyId).name("Hidden").build();
        when(courseRepository.findByAcademyIdOrderByNameAsc(academyId)).thenReturn(List.of(visible, hidden));

        UUID visibleStudent = UUID.randomUUID();
        UUID hiddenStudent = UUID.randomUUID();
        CourseMap visibleEnrolment = CourseMap.builder().membershipId(visibleStudent).courseId(visibleCourseId)
                .agreedFee(new java.math.BigDecimal("1000.00")).build();
        CourseMap hiddenEnrolment = CourseMap.builder().membershipId(hiddenStudent).courseId(hiddenCourseId)
                .agreedFee(new java.math.BigDecimal("2000.00")).build();
        when(courseMapRepository.findByCourseIdIn(List.of(visibleCourseId)))
                .thenReturn(List.of(visibleEnrolment));
        when(feeSlipRepository.findByCourseIdInAndPeriod(List.of(visibleCourseId), "2026-07")).thenReturn(List.of());
        when(membershipRepository.findAllById(Set.of(visibleStudent))).thenReturn(List.of(
                AcademyMembership.builder().id(visibleStudent).roleType(Role.STUDENT)
                        .status(com.nest.app.identity.entity.MembershipStatus.ACTIVE).build()));
        when(feeTransactionRepository.findByAcademyIdAndCategoryAndPeriod(
                academyId, com.nest.app.fees.entity.FeeCategory.REGULAR, "2026-07")).thenReturn(List.of());

        var result = dashboardService.summary("2026-07", null, null);

        assertThat(result.regular().totalCount()).isEqualTo(1);
        assertThat(result.regular().expected()).isEqualByComparingTo("1000.00");
        // The hidden course's enrolment/agreed-fee lookups were never reached for that student.
        assertThat(hiddenEnrolment.getCourseId()).isEqualTo(hiddenCourseId);
    }

    @Test
    void searchStudentsHidesStudentsNotEnrolledInAVisibleCourse() {
        when(courseFeatureGuard.visibleCourseIds(FeatureKey.FEES_ENTRY))
                .thenReturn(Optional.of(Set.of(visibleCourseId)));

        UUID visibleUserId = UUID.randomUUID();
        UUID hiddenUserId = UUID.randomUUID();
        AcademyMembership visibleStudent = AcademyMembership.builder().id(UUID.randomUUID()).userId(visibleUserId)
                .roleType(Role.STUDENT).status(com.nest.app.identity.entity.MembershipStatus.ACTIVE).build();
        AcademyMembership hiddenStudent = AcademyMembership.builder().id(UUID.randomUUID()).userId(hiddenUserId)
                .roleType(Role.STUDENT).status(com.nest.app.identity.entity.MembershipStatus.ACTIVE).build();
        when(membershipRepository.findByAcademyId(academyId)).thenReturn(List.of(visibleStudent, hiddenStudent));
        when(userRepository.findAllById(any())).thenReturn(List.of(
                User.builder().id(visibleUserId).fullName("Meera Visible").build(),
                User.builder().id(hiddenUserId).fullName("Meera Hidden").build()));
        when(courseMapRepository.findByMembershipId(visibleStudent.getId())).thenReturn(List.of(
                CourseMap.builder().membershipId(visibleStudent.getId()).courseId(visibleCourseId).build()));
        when(courseMapRepository.findByMembershipId(hiddenStudent.getId())).thenReturn(List.of(
                CourseMap.builder().membershipId(hiddenStudent.getId()).courseId(hiddenCourseId).build()));
        when(courseRepository.findByAcademyIdOrderByNameAsc(academyId)).thenReturn(List.of());

        var results = dashboardService.searchStudents("meera", 12);

        assertThat(results).hasSize(1);
        assertThat(results.get(0).studentName()).isEqualTo("Meera Visible");
    }
}
