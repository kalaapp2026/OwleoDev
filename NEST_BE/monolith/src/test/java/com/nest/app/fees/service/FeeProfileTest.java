package com.nest.app.fees.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchStatus;
import com.nest.app.enrolment.entity.BatchType;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.fees.dto.PaymentStatus;
import com.nest.app.fees.dto.StudentFeeProfileResponse;
import com.nest.app.fees.dto.UpdateAgreedFeeRequest;
import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.entity.FeeMode;
import com.nest.app.fees.entity.FeeTransaction;
import com.nest.app.fees.repository.FeeSlipRepository;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.common.exception.ResourceNotFoundException;
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

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyIterable;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The per-student fee profile, which is what the payment recorder is driven from - so what it
 * includes and excludes decides which course an admin can put money against.
 */
@ExtendWith(MockitoExtension.class)
class FeeProfileTest {

    @Mock private FeeTransactionRepository feeTransactionRepository;
    @Mock private CourseMapRepository courseMapRepository;
    @Mock private FeeSlipRepository feeSlipRepository;
    @Mock private CourseRepository courseRepository;
    @Mock private AcademyMembershipRepository membershipRepository;
    @Mock private UserRepository userRepository;
    @Mock private CourseFeatureGuard courseFeatureGuard;
    @Mock private BatchMemberRepository batchMemberRepository;
    @Mock private BatchRepository batchRepository;

    private FeesService feesService;

    private final UUID academyId = UUID.randomUUID();
    private final UUID membershipId = UUID.randomUUID();
    private final UUID userId = UUID.randomUUID();
    private final UUID guitarId = UUID.randomUUID();
    private final UUID pianoId = UUID.randomUUID();
    private static final String PERIOD = "2026-08";

    @BeforeEach
    void setUp() {
        feesService = new FeesService(feeTransactionRepository, courseMapRepository, feeSlipRepository,
                courseRepository, membershipRepository, userRepository, courseFeatureGuard,
                batchMemberRepository, batchRepository);
        UUID adminMembershipId = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN,
                List.of(new MembershipClaim(adminMembershipId, academyId, "Kalakshetra",
                        Role.ACADEMY_ADMIN, Set.of(), Set.of(guitarId, pianoId))),
                adminMembershipId));
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private AcademyMembership student() {
        return AcademyMembership.builder().id(membershipId).userId(userId).academyId(academyId)
                .roleType(Role.STUDENT).status(MembershipStatus.ACTIVE).build();
    }

    private CourseMap enrolment(UUID courseId, String fee, boolean active) {
        return CourseMap.builder().membershipId(membershipId).courseId(courseId)
                .agreedFee(new BigDecimal(fee)).active(active).build();
    }

    private Course course(UUID id, String name) {
        Course c = new Course();
        c.setId(id);
        c.setName(name);
        return c;
    }

    private FeeTransaction payment(UUID courseId, String amount, FeeMode mode) {
        return FeeTransaction.builder()
                .id(UUID.randomUUID()).academyId(academyId).category(FeeCategory.REGULAR)
                .membershipId(membershipId).courseId(courseId).period(PERIOD)
                .amountPaid(new BigDecimal(amount)).mode(mode)
                .occurredOn(LocalDate.now()).createdAt(Instant.now())
                .build();
    }

    private void wire(List<CourseMap> enrolments, List<FeeTransaction> transactions,
                      List<Batch> batches) {
        when(membershipRepository.findById(membershipId)).thenReturn(Optional.of(student()));
        when(courseMapRepository.findByMembershipId(membershipId)).thenReturn(enrolments);
        lenient().when(courseRepository.findAllById(anyIterable()))
                .thenReturn(List.of(course(guitarId, "Guitar Beginner"), course(pianoId, "Piano Basics")));
        lenient().when(courseFeatureGuard.hasCourseFeature(any(), any())).thenReturn(true);
        lenient().when(batchMemberRepository.findByMembershipId(membershipId)).thenReturn(
                batches.stream().map(b -> BatchMember.builder().batchId(b.getId())
                        .membershipId(membershipId).build()).toList());
        lenient().when(batchRepository.findAllById(anyIterable())).thenReturn(batches);
        lenient().when(feeSlipRepository.findByMembershipIdOrderByGeneratedAtDesc(membershipId))
                .thenReturn(List.of());
        lenient().when(feeTransactionRepository.findByMembershipIdAndPeriod(membershipId, PERIOD))
                .thenReturn(transactions);
        User u = new User();
        u.setId(userId);
        u.setFullName("Savish Holla");
        lenient().when(userRepository.findById(userId)).thenReturn(Optional.of(u));
    }

    @Test
    void listsEveryCourseTheStudentIsEnrolledIn() {
        // The recorder makes the admin pick a course, which it can only do if the server says what
        // the options are.
        wire(List.of(enrolment(guitarId, "1000", true), enrolment(pianoId, "1200", true)),
                List.of(payment(guitarId, "1000", FeeMode.CASH)),
                List.of());

        var profile = feesService.feeProfile(membershipId, PERIOD);

        assertThat(profile.studentName()).isEqualTo("Savish Holla");
        assertThat(profile.courses()).hasSize(2);
        assertThat(profile.totalAgreedFee()).isEqualByComparingTo("2200");
        assertThat(profile.totalPaid()).isEqualByComparingTo("1000");
        assertThat(profile.totalBalance()).isEqualByComparingTo("1200");
        assertThat(rowFor(profile, guitarId).status()).isEqualTo(PaymentStatus.PAID_MANUAL);
        assertThat(rowFor(profile, pianoId).status()).isEqualTo(PaymentStatus.NOT_PAID);
    }

    @Test
    void aDeactivatedEnrolmentIsNotBilled() {
        // Deactivating a student from one course stops it showing for them - it must not keep
        // appearing on their profile as money owed.
        wire(List.of(enrolment(guitarId, "1000", true), enrolment(pianoId, "1200", false)),
                List.of(), List.of());

        var profile = feesService.feeProfile(membershipId, PERIOD);

        assertThat(profile.courses()).hasSize(1);
        assertThat(profile.courses().get(0).courseId()).isEqualTo(guitarId);
        assertThat(profile.totalAgreedFee()).isEqualByComparingTo("1000");
    }

    @Test
    void anEnrolmentWithNoAgreedFeeIsSkipped() {
        // A trainer's course-map row has no fee concept at all; billing one would invent a debt.
        CourseMap noFee = CourseMap.builder().membershipId(membershipId).courseId(pianoId)
                .agreedFee(null).active(true).build();
        wire(List.of(enrolment(guitarId, "1000", true), noFee), List.of(), List.of());

        assertThat(feesService.feeProfile(membershipId, PERIOD).courses()).hasSize(1);
    }

    @Test
    void onlyCoursesTheCallerMaySeeAreIncluded() {
        // A trainer with FEES_ENTRY on one course must not learn what the student pays for another.
        wire(List.of(enrolment(guitarId, "1000", true), enrolment(pianoId, "1200", true)),
                List.of(), List.of());
        when(courseFeatureGuard.hasCourseFeature(guitarId, FeatureKey.FEES_ENTRY)).thenReturn(true);
        when(courseFeatureGuard.hasCourseFeature(pianoId, FeatureKey.FEES_ENTRY)).thenReturn(false);

        var profile = feesService.feeProfile(membershipId, PERIOD);

        assertThat(profile.courses()).hasSize(1);
        assertThat(profile.courses().get(0).courseId()).isEqualTo(guitarId);
        // Totals cover what was returned, so the stat boxes can't total something the list omits.
        assertThat(profile.totalAgreedFee()).isEqualByComparingTo("1000");
    }

    @Test
    void carriesTheBatchNameAsContext() {
        Batch batch = Batch.builder().id(UUID.randomUUID()).courseId(guitarId).name("Batch A")
                .batchType(BatchType.REGULAR).status(BatchStatus.ACTIVE).build();
        wire(List.of(enrolment(guitarId, "1000", true)), List.of(), List.of(batch));

        assertThat(rowFor(feesService.feeProfile(membershipId, PERIOD), guitarId).batchName())
                .isEqualTo("Batch A");
    }

    @Test
    void aReversalLeavesTheCourseUnpaidAgain() {
        FeeTransaction paid = payment(guitarId, "1000", FeeMode.CASH);
        FeeTransaction reversal = payment(guitarId, "-1000", FeeMode.CASH);
        reversal.setReversalOfTransactionId(paid.getId());
        wire(List.of(enrolment(guitarId, "1000", true)), List.of(paid, reversal), List.of());

        var row = rowFor(feesService.feeProfile(membershipId, PERIOD), guitarId);

        assertThat(row.totalPaid()).isEqualByComparingTo("0");
        assertThat(row.status()).isEqualTo(PaymentStatus.NOT_PAID);
        assertThat(row.lastPaymentId()).isNull();
    }

    @Test
    void anotherAcademysStudentIsNotFound() {
        AcademyMembership foreign = AcademyMembership.builder().id(membershipId).userId(userId)
                .academyId(UUID.randomUUID()).roleType(Role.STUDENT)
                .status(MembershipStatus.ACTIVE).build();
        when(membershipRepository.findById(membershipId)).thenReturn(Optional.of(foreign));

        assertThatThrownBy(() -> feesService.feeProfile(membershipId, PERIOD))
                .isInstanceOf(ResourceNotFoundException.class);
    }

    // ---- editing the agreed fee ----

    @Test
    void updatingTheAgreedFeeWritesOnlyTheFee() {
        // Nothing recalculates and no status is stored: status is derived, so the next read simply
        // compares the new fee against the same ledger.
        CourseMap enrolment = enrolment(guitarId, "1000", true);
        when(membershipRepository.findById(membershipId)).thenReturn(Optional.of(student()));
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, guitarId))
                .thenReturn(Optional.of(enrolment));
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, guitarId))
                .thenReturn(Optional.of(enrolment));
        when(feeTransactionRepository.sumPaid(any(), any(), any())).thenReturn(new BigDecimal("1000"));

        feesService.updateAgreedFee(
                new UpdateAgreedFeeRequest(membershipId, guitarId, new BigDecimal("1200")));

        ArgumentCaptor<CourseMap> saved = ArgumentCaptor.forClass(CourseMap.class);
        verify(courseMapRepository).save(saved.capture());
        assertThat(saved.getValue().getAgreedFee()).isEqualByComparingTo("1200");
        // No transaction is written - changing what is charged is not a payment.
        verify(feeTransactionRepository, org.mockito.Mockito.never())
                .saveAndFlush(any(FeeTransaction.class));
    }

    @Test
    void aFullScholarshipIsZero() {
        // Zero is a real agreed fee, distinct from having no enrolment at all.
        CourseMap enrolment = enrolment(guitarId, "1000", true);
        when(membershipRepository.findById(membershipId)).thenReturn(Optional.of(student()));
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, guitarId))
                .thenReturn(Optional.of(enrolment));
        when(feeTransactionRepository.sumPaid(any(), any(), any())).thenReturn(BigDecimal.ZERO);

        feesService.updateAgreedFee(
                new UpdateAgreedFeeRequest(membershipId, guitarId, BigDecimal.ZERO));

        assertThat(enrolment.getAgreedFee()).isEqualByComparingTo("0");
    }

    @Test
    void cannotSetAFeeForACourseTheStudentIsNotEnrolledIn() {
        when(membershipRepository.findById(membershipId)).thenReturn(Optional.of(student()));
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, pianoId))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> feesService.updateAgreedFee(
                new UpdateAgreedFeeRequest(membershipId, pianoId, new BigDecimal("500"))))
                .isInstanceOf(ResourceNotFoundException.class)
                .hasMessageContaining("not enrolled");
    }

    @Test
    void cannotSetAFeeForAnotherAcademysStudent() {
        AcademyMembership foreign = AcademyMembership.builder().id(membershipId).userId(userId)
                .academyId(UUID.randomUUID()).roleType(Role.STUDENT)
                .status(MembershipStatus.ACTIVE).build();
        when(membershipRepository.findById(membershipId)).thenReturn(Optional.of(foreign));

        assertThatThrownBy(() -> feesService.updateAgreedFee(
                new UpdateAgreedFeeRequest(membershipId, guitarId, new BigDecimal("500"))))
                .isInstanceOf(ResourceNotFoundException.class);
    }

    private StudentFeeProfileResponse.CourseFeeRow rowFor(StudentFeeProfileResponse profile, UUID courseId) {
        return profile.courses().stream().filter(c -> c.courseId().equals(courseId)).findFirst()
                .orElseThrow(() -> new AssertionError("no row for course " + courseId));
    }
}
