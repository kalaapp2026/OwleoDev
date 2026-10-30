package com.nest.app.enrolment.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.dto.CreateCourseChangeRequest;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchStatus;
import com.nest.app.enrolment.entity.BatchType;
import com.nest.app.enrolment.entity.StudentCourseChange;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.enrolment.repository.StudentCourseChangeRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
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
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.PlatformTransactionManager;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * A student moved from Basic to Advanced from next month: nothing changes the day it is scheduled, and on
 * the day the new course is billed and the old one is not.
 */
@ExtendWith(MockitoExtension.class)
class CourseChangeServiceTest {

    @Mock private StudentCourseChangeRepository changeRepository;
    @Mock private AcademyMembershipRepository membershipRepository;
    @Mock private CourseRepository courseRepository;
    @Mock private CourseMapRepository courseMapRepository;
    @Mock private BatchRepository batchRepository;
    @Mock private BatchMemberRepository batchMemberRepository;
    @Mock private CourseFeatureGuard courseFeatureGuard;
    @Mock private PlatformTransactionManager transactionManager;

    private CourseChangeService service;

    private final UUID academyId = UUID.randomUUID();
    private final UUID student = UUID.randomUUID();
    private final UUID basic = UUID.randomUUID();
    private final UUID advanced = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new CourseChangeService(changeRepository, membershipRepository, courseRepository, courseMapRepository,
                batchRepository, batchMemberRepository, courseFeatureGuard, transactionManager);
        UUID admin = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "admin", Role.ACADEMY_ADMIN,
                List.of(new MembershipClaim(admin, academyId, "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of())), admin));

        lenient().when(membershipRepository.findById(student)).thenReturn(Optional.of(
                AcademyMembership.builder().id(student).academyId(academyId).roleType(Role.STUDENT).build()));
        lenient().when(courseRepository.findById(basic)).thenReturn(Optional.of(course(basic, "Basic", null)));
        lenient().when(courseRepository.findById(advanced)).thenReturn(Optional.of(course(advanced, "Advanced", "3000")));
        lenient().when(courseMapRepository.findByMembershipIdAndCourseId(student, basic)).thenReturn(Optional.of(
                CourseMap.builder().membershipId(student).courseId(basic).agreedFee(new BigDecimal("1500")).build()));
        lenient().when(changeRepository.save(any(StudentCourseChange.class))).thenAnswer(inv -> {
            StudentCourseChange c = inv.getArgument(0);
            if (c.getId() == null) {
                c.setId(UUID.randomUUID());
            }
            return c;
        });
        lenient().when(batchRepository.findAllById(any())).thenReturn(List.of());
        lenient().when(courseRepository.findAllById(any())).thenReturn(List.of());
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private Course course(UUID id, String name, String fee) {
        return Course.builder().id(id).academyId(academyId).name(name).status(CourseStatus.ACTIVE)
                .defaultFee(fee == null ? null : new BigDecimal(fee)).build();
    }

    // ---------------------------------------------------------------- scheduling

    @Test
    void theMoveStartsOnTheFirstOfNextMonthByDefault() {
        var response = service.schedule(student, new CreateCourseChangeRequest(basic, advanced, null, null));

        assertThat(response.effectiveOn()).isEqualTo(LocalDate.now().withDayOfMonth(1).plusMonths(1));
        assertThat(response.status()).isEqualTo("PENDING");
    }

    @Test
    void firstOfNextMonthCrossesTheYearEnd() {
        assertThat(CourseChangeService.firstOfNextMonth(LocalDate.of(2026, 12, 20))).isEqualTo(LocalDate.of(2027, 1, 1));
        assertThat(CourseChangeService.firstOfNextMonth(LocalDate.of(2026, 10, 1))).isEqualTo(LocalDate.of(2026, 11, 1));
    }

    @Test
    void schedulingNeedsTheStudentRegistrationPermissionOnBothCourses() {
        service.schedule(student, new CreateCourseChangeRequest(basic, advanced, null, null));

        verify(courseFeatureGuard).assertCourseFeature(basic, FeatureKey.STUDENT_REGISTRATION);
        verify(courseFeatureGuard).assertCourseFeature(advanced, FeatureKey.STUDENT_REGISTRATION);
    }

    @Test
    void aTrainerWithoutTheNewCourseIsRefused() {
        lenient().doThrow(new ForbiddenException("nope")).when(courseFeatureGuard)
                .assertCourseFeature(advanced, FeatureKey.STUDENT_REGISTRATION);

        assertThatThrownBy(() -> service.schedule(student, new CreateCourseChangeRequest(basic, advanced, null, null)))
                .isInstanceOf(ForbiddenException.class);
        verify(changeRepository, never()).save(any());
    }

    @Test
    void aMoveToTodayOrThePastIsRefused() {
        assertThatThrownBy(() -> service.schedule(student,
                new CreateCourseChangeRequest(basic, advanced, LocalDate.now(), null)))
                .isInstanceOf(BadRequestException.class).hasMessageContaining("future date");
    }

    @Test
    void youCannotMoveSomeoneOutOfACourseTheyAreNotIn() {
        when(courseMapRepository.findByMembershipIdAndCourseId(student, basic)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.schedule(student, new CreateCourseChangeRequest(basic, advanced, null, null)))
                .isInstanceOf(BadRequestException.class).hasMessageContaining("not enrolled");
    }

    @Test
    void aSecondMoveOutOfTheSameCourseWaitsForTheFirst() {
        when(changeRepository.existsByMembershipIdAndFromCourseIdAndStatus(student, basic, StudentCourseChange.Status.PENDING))
                .thenReturn(true);

        assertThatThrownBy(() -> service.schedule(student, new CreateCourseChangeRequest(basic, advanced, null, null)))
                .isInstanceOf(ConflictException.class);
    }

    @Test
    void aBatchThatDoesNotTeachTheNewCourseCannotBeChosen() {
        Batch other = Batch.builder().id(UUID.randomUUID()).name("Basic only").status(BatchStatus.ACTIVE)
                .batchType(BatchType.REGULAR).build();
        other.setCourses(List.of(basic));
        when(batchRepository.findAllById(any())).thenReturn(List.of(other));

        assertThatThrownBy(() -> service.schedule(student,
                new CreateCourseChangeRequest(basic, advanced, null, List.of(other.getId()))))
                .isInstanceOf(BadRequestException.class).hasMessageContaining("not a batch of Advanced");
    }

    // ---------------------------------------------------------------- applying

    private StudentCourseChange due(UUID... toBatches) {
        StudentCourseChange c = StudentCourseChange.builder().id(UUID.randomUUID()).membershipId(student)
                .fromCourseId(basic).toCourseId(advanced).effectiveOn(LocalDate.now().minusDays(1))
                .createdBy(UUID.randomUUID())
                .toBatchIds(toBatches.length == 0 ? null
                        : String.join(",", java.util.Arrays.stream(toBatches).map(UUID::toString).toList()))
                .build();
        when(changeRepository.findByStatusAndEffectiveOnLessThanEqual(any(), any())).thenReturn(List.of(c));
        when(changeRepository.findById(c.getId())).thenReturn(Optional.of(c));
        return c;
    }

    @Test
    void onTheDayTheNewCourseIsBilledAndTheOldOneIsNot() {
        StudentCourseChange change = due();

        int applied = service.applyDue(LocalDate.now());

        assertThat(applied).isEqualTo(1);
        ArgumentCaptor<CourseMap> saved = ArgumentCaptor.forClass(CourseMap.class);
        verify(courseMapRepository, org.mockito.Mockito.times(2)).save(saved.capture());
        CourseMap into = saved.getAllValues().stream().filter(m -> m.getCourseId().equals(advanced)).findFirst().orElseThrow();
        CourseMap out = saved.getAllValues().stream().filter(m -> m.getCourseId().equals(basic)).findFirst().orElseThrow();
        assertThat(into.isActive()).isTrue();
        assertThat(into.getAgreedFee()).isEqualByComparingTo("3000");
        assertThat(out.isActive()).isFalse();
        assertThat(change.getStatus()).isEqualTo(StudentCourseChange.Status.APPLIED);
        assertThat(change.getAppliedAt()).isNotNull();
    }

    @Test
    void anOldEnrolmentInTheNewCourseIsSwitchedBackOnRatherThanDuplicated() {
        CourseMap earlier = CourseMap.builder().membershipId(student).courseId(advanced).active(false)
                .agreedFee(new BigDecimal("2800")).build();
        when(courseMapRepository.findByMembershipIdAndCourseId(student, advanced)).thenReturn(Optional.of(earlier));
        due();

        service.applyDue(LocalDate.now());

        assertThat(earlier.isActive()).isTrue();
        assertThat(earlier.getAgreedFee()).isEqualByComparingTo("2800"); // the fee agreed back then stands
    }

    @Test
    void theStudentLeavesARegularBatchThatOnlyTaughtTheOldCourse() {
        Batch basicOnly = Batch.builder().id(UUID.randomUUID()).name("Basic Sat").batchType(BatchType.REGULAR).build();
        basicOnly.setCourses(List.of(basic));
        Batch combined = Batch.builder().id(UUID.randomUUID()).name("All levels").batchType(BatchType.REGULAR).build();
        combined.setCourses(List.of(basic, advanced));
        when(batchMemberRepository.findByMembershipId(student)).thenReturn(List.of(
                BatchMember.builder().batchId(basicOnly.getId()).membershipId(student).build(),
                BatchMember.builder().batchId(combined.getId()).membershipId(student).build()));
        when(batchRepository.findAllById(any())).thenReturn(List.of(basicOnly, combined));
        due();

        service.applyDue(LocalDate.now());

        verify(batchMemberRepository).deleteByBatchIdAndMembershipId(basicOnly.getId(), student);
        verify(batchMemberRepository, never()).deleteByBatchIdAndMembershipId(combined.getId(), student);
    }

    @Test
    void theStudentIsPlacedInTheChosenBatchOfTheNewCourse() {
        Batch advancedBatch = Batch.builder().id(UUID.randomUUID()).name("Advanced Sat").batchType(BatchType.REGULAR).build();
        advancedBatch.setCourses(List.of(advanced));
        when(batchRepository.findById(advancedBatch.getId())).thenReturn(Optional.of(advancedBatch));
        when(batchMemberRepository.findByMembershipId(student)).thenReturn(List.of());
        due(advancedBatch.getId());

        service.applyDue(LocalDate.now());

        ArgumentCaptor<BatchMember> seat = ArgumentCaptor.forClass(BatchMember.class);
        verify(batchMemberRepository).save(seat.capture());
        assertThat(seat.getValue().getBatchId()).isEqualTo(advancedBatch.getId());
        assertThat(seat.getValue().getMembershipId()).isEqualTo(student);
    }

    @Test
    void aMoveThatAlreadyHappenedIsNotAppliedTwice() {
        StudentCourseChange change = due();
        change.setStatus(StudentCourseChange.Status.APPLIED);

        service.applyDue(LocalDate.now());

        verify(courseMapRepository, never()).save(any());
    }

    @Test
    void oneMoveThatCannotBeAppliedDoesNotStopTheOthers() {
        StudentCourseChange broken = StudentCourseChange.builder().id(UUID.randomUUID()).membershipId(student)
                .fromCourseId(basic).toCourseId(UUID.randomUUID()).effectiveOn(LocalDate.now().minusDays(1))
                .createdBy(UUID.randomUUID()).build();
        StudentCourseChange fine = StudentCourseChange.builder().id(UUID.randomUUID()).membershipId(student)
                .fromCourseId(basic).toCourseId(advanced).effectiveOn(LocalDate.now().minusDays(1))
                .createdBy(UUID.randomUUID()).build();
        when(changeRepository.findByStatusAndEffectiveOnLessThanEqual(any(), any())).thenReturn(List.of(broken, fine));
        when(changeRepository.findById(broken.getId())).thenReturn(Optional.of(broken));
        when(changeRepository.findById(fine.getId())).thenReturn(Optional.of(fine));
        when(courseRepository.findById(broken.getToCourseId())).thenReturn(Optional.empty());

        int applied = service.applyDue(LocalDate.now());

        assertThat(applied).isEqualTo(1);
        assertThat(fine.getStatus()).isEqualTo(StudentCourseChange.Status.APPLIED);
        assertThat(broken.getStatus()).isEqualTo(StudentCourseChange.Status.PENDING);
    }

    // ---------------------------------------------------------------- cancelling

    @Test
    void aPendingMoveCanBeCancelled() {
        StudentCourseChange change = StudentCourseChange.builder().id(UUID.randomUUID()).membershipId(student)
                .fromCourseId(basic).toCourseId(advanced).effectiveOn(LocalDate.now().plusDays(5))
                .createdBy(UUID.randomUUID()).build();
        when(changeRepository.findById(change.getId())).thenReturn(Optional.of(change));
        when(courseFeatureGuard.hasCourseFeature(basic, FeatureKey.STUDENT_REGISTRATION)).thenReturn(true);

        service.cancel(change.getId());

        assertThat(change.getStatus()).isEqualTo(StudentCourseChange.Status.CANCELLED);
    }

    @Test
    void aMoveThatAlreadyHappenedCannotBeCancelled() {
        StudentCourseChange change = StudentCourseChange.builder().id(UUID.randomUUID()).membershipId(student)
                .fromCourseId(basic).toCourseId(advanced).effectiveOn(LocalDate.now().minusDays(5))
                .status(StudentCourseChange.Status.APPLIED).createdBy(UUID.randomUUID()).build();
        when(changeRepository.findById(change.getId())).thenReturn(Optional.of(change));
        when(courseFeatureGuard.hasCourseFeature(basic, FeatureKey.STUDENT_REGISTRATION)).thenReturn(true);

        assertThatThrownBy(() -> service.cancel(change.getId())).isInstanceOf(ConflictException.class);
    }

    @Test
    void someoneWithNeitherCourseCannotCancelIt() {
        StudentCourseChange change = StudentCourseChange.builder().id(UUID.randomUUID()).membershipId(student)
                .fromCourseId(basic).toCourseId(advanced).effectiveOn(LocalDate.now().plusDays(5))
                .createdBy(UUID.randomUUID()).build();
        when(changeRepository.findById(change.getId())).thenReturn(Optional.of(change));

        assertThatThrownBy(() -> service.cancel(change.getId())).isInstanceOf(ForbiddenException.class);
        assertThat(change.getStatus()).isEqualTo(StudentCourseChange.Status.PENDING);
    }
}
