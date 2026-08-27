package com.nest.app.fees.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.fees.dto.PaymentStatus;
import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.entity.FeeMode;
import com.nest.app.fees.entity.FeeSlip;
import com.nest.app.fees.entity.FeeSlipStatus;
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

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyIterable;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

/** The statement: which periods appear, and what the totals describe. */
@ExtendWith(MockitoExtension.class)
class FeeStatementTest {

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
    private final UUID courseId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        feesService = new FeesService(feeTransactionRepository, courseMapRepository, feeSlipRepository,
                courseRepository, membershipRepository, userRepository, courseFeatureGuard,
                batchMemberRepository, batchRepository);
        UUID adminMembershipId = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN,
                List.of(new MembershipClaim(adminMembershipId, academyId, "Kalakshetra",
                        Role.ACADEMY_ADMIN, Set.of(), Set.of(courseId))),
                adminMembershipId));
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private FeeTransaction payment(String period, String amount, LocalDate on) {
        return FeeTransaction.builder()
                .id(UUID.randomUUID()).academyId(academyId).category(FeeCategory.REGULAR)
                .membershipId(membershipId).courseId(courseId).period(period)
                .amountPaid(new BigDecimal(amount)).mode(FeeMode.CASH)
                .occurredOn(on).createdAt(Instant.now())
                .build();
    }

    private FeeSlip slip(String period, String due, FeeSlipStatus status) {
        return FeeSlip.builder().id(UUID.randomUUID()).membershipId(membershipId).courseId(courseId)
                .period(period).amountDue(new BigDecimal(due))
                .billingPeriodStart(LocalDate.now().minusDays(30))
                .billingPeriodEnd(LocalDate.now().minusDays(1))
                .status(status).build();
    }

    private void wire(List<FeeSlip> slips, List<FeeTransaction> transactions) {
        when(membershipRepository.findById(membershipId)).thenReturn(Optional.of(
                AcademyMembership.builder().id(membershipId).userId(userId).academyId(academyId)
                        .roleType(Role.STUDENT).status(MembershipStatus.ACTIVE).build()));
        when(courseMapRepository.findByMembershipId(membershipId)).thenReturn(List.of(
                CourseMap.builder().membershipId(membershipId).courseId(courseId)
                        .agreedFee(new BigDecimal("1000")).active(true).build()));
        lenient().when(courseFeatureGuard.hasCourseFeature(any(), any())).thenReturn(true);
        Course c = new Course();
        c.setId(courseId);
        c.setName("Guitar Beginner");
        lenient().when(courseRepository.findAllById(anyIterable())).thenReturn(List.of(c));
        lenient().when(feeSlipRepository.findByMembershipIdOrderByGeneratedAtDesc(membershipId))
                .thenReturn(slips);
        lenient().when(feeTransactionRepository.findByMembershipIdOrderByCreatedAtDesc(membershipId))
                .thenReturn(transactions);
        User u = new User();
        u.setId(userId);
        u.setFullName("Savish Holla");
        lenient().when(userRepository.findById(userId)).thenReturn(Optional.of(u));
    }

    @Test
    void aPeriodPaidWithoutASlipStillAppears() {
        // Money taken must never be missing from the document meant to account for it, even if
        // auto-billing never generated a slip for that month.
        wire(List.of(), List.of(payment("2026-07", "1000", LocalDate.of(2026, 7, 4))));

        var statement = feesService.statement(membershipId, null);

        assertThat(statement.rows()).hasSize(1);
        assertThat(statement.rows().get(0).label()).isEqualTo("2026-07");
        assertThat(statement.rows().get(0).context()).isEqualTo("Guitar Beginner");
        assertThat(statement.totalPaid()).isEqualByComparingTo("1000");
    }

    @Test
    void aBilledPeriodWithNoPaymentAppearsAsOwing() {
        wire(List.of(slip("2026-08", "1000", FeeSlipStatus.OPEN)), List.of());

        var statement = feesService.statement(membershipId, null);

        assertThat(statement.rows()).hasSize(1);
        assertThat(statement.rows().get(0).paid()).isEqualByComparingTo("0");
        assertThat(statement.outstanding()).isEqualByComparingTo("1000");
        // Past its billing period with nothing paid, so it has run out of road.
        assertThat(statement.rows().get(0).status()).isEqualTo(PaymentStatus.DUE);
    }

    @Test
    void instalmentsAgainstOneMonthAreOneLine() {
        // A month settled in three payments is one thing the family owed, not three.
        wire(List.of(slip("2026-08", "1000", FeeSlipStatus.OPEN)), List.of(
                payment("2026-08", "300", LocalDate.of(2026, 8, 2)),
                payment("2026-08", "300", LocalDate.of(2026, 8, 10)),
                payment("2026-08", "400", LocalDate.of(2026, 8, 20))));

        var statement = feesService.statement(membershipId, null);

        assertThat(statement.rows()).hasSize(1);
        assertThat(statement.rows().get(0).paid()).isEqualByComparingTo("1000");
        // Grouped under the most recent payment, which is when the debt was actually cleared.
        assertThat(statement.rows().get(0).paidOn()).isEqualTo(LocalDate.of(2026, 8, 20));
    }

    @Test
    void aReversedPaymentLeavesThePeriodOwingAgain() {
        FeeTransaction paid = payment("2026-08", "1000", LocalDate.of(2026, 8, 3));
        FeeTransaction reversal = payment("2026-08", "-1000", LocalDate.of(2026, 8, 5));
        reversal.setReversalOfTransactionId(paid.getId());
        wire(List.of(slip("2026-08", "1000", FeeSlipStatus.OPEN)), List.of(paid, reversal));

        var statement = feesService.statement(membershipId, null);

        assertThat(statement.rows().get(0).paid()).isEqualByComparingTo("0");
        assertThat(statement.outstanding()).isEqualByComparingTo("1000");
        // Nothing stands as a payment, so the row has no date to be filed under.
        assertThat(statement.rows().get(0).paidOn()).isNull();
    }

    @Test
    void unpaidPeriodsSortAfterPaidOnes() {
        // Unpaid rows have no date to place them, and they are what the reader must act on - so
        // they collect at the end rather than being scattered through the history.
        wire(List.of(slip("2026-08", "1000", FeeSlipStatus.OPEN)),
                List.of(payment("2026-06", "1000", LocalDate.of(2026, 6, 4)),
                        payment("2026-07", "1000", LocalDate.of(2026, 7, 4))));

        var rows = feesService.statement(membershipId, null).rows();

        assertThat(rows).hasSize(3);
        assertThat(rows.get(0).label()).isEqualTo("2026-07");
        assertThat(rows.get(1).label()).isEqualTo("2026-06");
        assertThat(rows.get(2).label()).isEqualTo("2026-08");
        assertThat(rows.get(2).paidOn()).isNull();
    }

    @Test
    void filteringToOtherEmptiesTheTotalsAsWellAsTheRows() {
        // The summary must describe the rows on screen, not a dataset the reader can't see.
        wire(List.of(), List.of(payment("2026-07", "1000", LocalDate.of(2026, 7, 4))));

        var statement = feesService.statement(membershipId, FeeCategory.OTHER);

        assertThat(statement.rows()).isEmpty();
        assertThat(statement.totalBilled()).isEqualByComparingTo("0");
        assertThat(statement.totalPaid()).isEqualByComparingTo("0");
        assertThat(statement.outstanding()).isEqualByComparingTo("0");
    }

    @Test
    void csvCarriesTheSameRowsAndTotalsAsTheScreen() {
        wire(List.of(slip("2026-08", "1000", FeeSlipStatus.OPEN)),
                List.of(payment("2026-08", "400", LocalDate.of(2026, 8, 12))));

        String csv = feesService.generateStatementCsv(membershipId, null);

        assertThat(csv).startsWith("Period,Category,Context,Fee,Paid,Balance,Status,Payment Date,Mode");
        // Text fields are quoted - a course named "Guitar, Advanced" must not split into two columns.
        assertThat(csv).contains("\"2026-08\",REGULAR,\"Guitar Beginner\",1000,400,600,PARTIAL,2026-08-12,CASH");
        assertThat(csv).contains("Total billed,1000");
        assertThat(csv).contains("Outstanding,600");
    }

    @Test
    void anotherAcademysStudentHasNoStatement() {
        when(membershipRepository.findById(membershipId)).thenReturn(Optional.of(
                AcademyMembership.builder().id(membershipId).userId(userId)
                        .academyId(UUID.randomUUID()).roleType(Role.STUDENT)
                        .status(MembershipStatus.ACTIVE).build()));

        assertThatThrownBy(() -> feesService.statement(membershipId, null))
                .isInstanceOf(ResourceNotFoundException.class);
    }
}
