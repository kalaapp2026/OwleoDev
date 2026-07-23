package com.nest.app.fees.service;

import com.nest.app.attendance.repository.AttendanceRepository;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.entity.FeeCycle;
import com.nest.app.curriculum.entity.FeeModel;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.fees.entity.FeeSlip;
import com.nest.app.fees.entity.FeeSlipStatus;
import com.nest.app.fees.repository.FeeSlipRepository;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.security.Role;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** Covers the two behaviours this billing-cycle rework adds: a quarterly/yearly course only
 * actually generates on its own cadence (not every month like a monthly one), and an unresolved
 * OPEN prior period's shortfall rolls into the next slip generated. */
@ExtendWith(MockitoExtension.class)
class FeeSlipServiceTest {

    @Mock
    private CourseRepository courseRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private CourseMapRepository courseMapRepository;
    @Mock
    private BatchRepository batchRepository;
    @Mock
    private BatchMemberRepository batchMemberRepository;
    @Mock
    private ClassInstanceRepository classInstanceRepository;
    @Mock
    private AttendanceRepository attendanceRepository;
    @Mock
    private FeeSlipRepository feeSlipRepository;
    @Mock
    private FeeTransactionRepository feeTransactionRepository;

    private FeeSlipService feeSlipService;

    private final UUID courseId = UUID.randomUUID();
    private final UUID membershipId = UUID.randomUUID();

    private FeeSlipService service() {
        return new FeeSlipService(courseRepository, membershipRepository, courseMapRepository, batchRepository,
                batchMemberRepository, classInstanceRepository, attendanceRepository, feeSlipRepository, feeTransactionRepository);
    }

    @Test
    void quarterlyCourseSkipsGenerationOffCycle() {
        feeSlipService = service();
        LocalDate today = LocalDate.now();
        Course course = Course.builder().id(courseId).feeCycle(FeeCycle.QUARTERLY).feeModel(FeeModel.FIXED)
                .defaultFee(new BigDecimal("3000.00"))
                .createdAt(today.minusMonths(1).atStartOfDay(java.time.ZoneOffset.UTC).toInstant()) // 1 month ago - not a 3-month boundary
                .billingDayOfMonth(today.getDayOfMonth())
                .status(CourseStatus.ACTIVE)
                .build();
        when(courseRepository.findByBillingDayOfMonthAndStatus(today.getDayOfMonth(), CourseStatus.ACTIVE)).thenReturn(List.of(course));

        feeSlipService.generateDueSlipsForToday();

        verify(courseMapRepository, never()).findByCourseId(any());
    }

    @Test
    void quarterlyCourseGeneratesOnItsOwnCycleBoundary() {
        feeSlipService = service();
        LocalDate today = LocalDate.now();
        Course course = Course.builder().id(courseId).feeCycle(FeeCycle.QUARTERLY).feeModel(FeeModel.FIXED)
                .defaultFee(new BigDecimal("3000.00"))
                .createdAt(today.minusMonths(3).atStartOfDay(java.time.ZoneOffset.UTC).toInstant()) // exactly 3 months ago - a boundary
                .billingDayOfMonth(today.getDayOfMonth())
                .status(CourseStatus.ACTIVE)
                .build();
        when(courseRepository.findByBillingDayOfMonthAndStatus(today.getDayOfMonth(), CourseStatus.ACTIVE)).thenReturn(List.of(course));
        when(courseMapRepository.findByCourseId(courseId)).thenReturn(List.of());

        feeSlipService.generateDueSlipsForToday();

        verify(courseMapRepository).findByCourseId(courseId);
    }

    @Test
    void carriedForwardAmountAddsUnpaidPriorPeriodOntoTheNewSlip() {
        feeSlipService = service();
        Course course = Course.builder().id(courseId).feeCycle(FeeCycle.MONTHLY).feeModel(FeeModel.FIXED)
                .defaultFee(new BigDecimal("1000.00")).createdAt(Instant.now()).build();

        when(courseMapRepository.findByCourseId(courseId)).thenReturn(
                List.of(CourseMap.builder().membershipId(membershipId).courseId(courseId).agreedFee(new BigDecimal("1000.00")).build()));
        when(membershipRepository.findAllById(java.util.Set.of(membershipId))).thenReturn(
                List.of(AcademyMembership.builder().id(membershipId).roleType(Role.STUDENT).status(MembershipStatus.ACTIVE).build()));
        when(batchRepository.findByCourseId(courseId)).thenReturn(List.of());
        when(feeSlipRepository.findByMembershipIdAndCourseIdAndPeriod(membershipId, courseId, "2026-07")).thenReturn(Optional.empty());
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId))
                .thenReturn(Optional.of(CourseMap.builder().membershipId(membershipId).courseId(courseId).agreedFee(new BigDecimal("1000.00")).build()));

        FeeSlip priorSlip = FeeSlip.builder().membershipId(membershipId).courseId(courseId).period("2026-06")
                .amountDue(new BigDecimal("1000.00")).status(FeeSlipStatus.OPEN).build();
        when(feeSlipRepository.findFirstByMembershipIdAndCourseIdAndPeriodLessThanOrderByPeriodDesc(membershipId, courseId, "2026-07"))
                .thenReturn(Optional.of(priorSlip));
        when(feeTransactionRepository.sumPaid(membershipId, courseId, "2026-06")).thenReturn(new BigDecimal("400.00"));
        when(feeSlipRepository.save(org.mockito.ArgumentMatchers.any(FeeSlip.class))).thenAnswer(inv -> inv.getArgument(0));

        List<FeeSlip> result = invokeGenerate(course, LocalDate.of(2026, 7, 5));

        assertThat(result).hasSize(1);
        assertThat(result.get(0).getCarriedForwardAmount()).isEqualByComparingTo("600.00");
        assertThat(result.get(0).getAmountDue()).isEqualByComparingTo("1600.00"); // 1000 new + 600 carried
    }

    @Test
    void closedPriorPeriodNeverCarriesForward() {
        feeSlipService = service();
        Course course = Course.builder().id(courseId).feeCycle(FeeCycle.MONTHLY).feeModel(FeeModel.FIXED)
                .defaultFee(new BigDecimal("1000.00")).createdAt(Instant.now()).build();

        when(courseMapRepository.findByCourseId(courseId)).thenReturn(
                List.of(CourseMap.builder().membershipId(membershipId).courseId(courseId).agreedFee(new BigDecimal("1000.00")).build()));
        when(membershipRepository.findAllById(java.util.Set.of(membershipId))).thenReturn(
                List.of(AcademyMembership.builder().id(membershipId).roleType(Role.STUDENT).status(MembershipStatus.ACTIVE).build()));
        when(batchRepository.findByCourseId(courseId)).thenReturn(List.of());
        when(feeSlipRepository.findByMembershipIdAndCourseIdAndPeriod(membershipId, courseId, "2026-07")).thenReturn(Optional.empty());
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId))
                .thenReturn(Optional.of(CourseMap.builder().membershipId(membershipId).courseId(courseId).agreedFee(new BigDecimal("1000.00")).build()));

        FeeSlip priorSlip = FeeSlip.builder().membershipId(membershipId).courseId(courseId).period("2026-06")
                .amountDue(new BigDecimal("1000.00")).status(FeeSlipStatus.CLOSED).build();
        when(feeSlipRepository.findFirstByMembershipIdAndCourseIdAndPeriodLessThanOrderByPeriodDesc(membershipId, courseId, "2026-07"))
                .thenReturn(Optional.of(priorSlip));
        when(feeSlipRepository.save(org.mockito.ArgumentMatchers.any(FeeSlip.class))).thenAnswer(inv -> inv.getArgument(0));

        List<FeeSlip> result = invokeGenerate(course, LocalDate.of(2026, 7, 5));

        assertThat(result).hasSize(1);
        assertThat(result.get(0).getCarriedForwardAmount()).isEqualByComparingTo("0.00");
        assertThat(result.get(0).getAmountDue()).isEqualByComparingTo("1000.00");
    }

    /** generateSlipsForCourse is protected, not private - same-package access from this test
     * needs no reflection. */
    private List<FeeSlip> invokeGenerate(Course course, LocalDate billingDate) {
        return feeSlipService.generateSlipsForCourse(course, billingDate);
    }
}
