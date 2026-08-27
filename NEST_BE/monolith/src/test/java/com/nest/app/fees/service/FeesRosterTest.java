package com.nest.app.fees.service;

import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
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
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
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
 * The roster's derived status and the reversal rules - the two pieces of fee logic that decide
 * what an admin sees and what they are allowed to undo.
 */
@ExtendWith(MockitoExtension.class)
class FeesRosterTest {

    @Mock private FeeTransactionRepository feeTransactionRepository;
    @Mock private CourseMapRepository courseMapRepository;
    @Mock private FeeSlipRepository feeSlipRepository;
    @Mock private CourseRepository courseRepository;
    @Mock private AcademyMembershipRepository membershipRepository;
    @Mock private UserRepository userRepository;
    @Mock private com.nest.app.identity.service.CourseFeatureGuard courseFeatureGuard;
    @Mock private BatchMemberRepository batchMemberRepository;
    @Mock private com.nest.app.enrolment.repository.BatchRepository batchRepository;

    private FeesService feesService;

    private final UUID academyId = UUID.randomUUID();
    private final UUID courseId = UUID.randomUUID();
    private final UUID batchId = UUID.randomUUID();
    private static final String PERIOD = "2026-08";

    private final List<AcademyMembership> memberships = new ArrayList<>();
    private final List<User> users = new ArrayList<>();
    private final List<CourseMap> courseMaps = new ArrayList<>();
    private final List<BatchMember> batchMembers = new ArrayList<>();

    @BeforeEach
    void setUp() {
        feesService = new FeesService(feeTransactionRepository, courseMapRepository, feeSlipRepository,
                courseRepository, membershipRepository, userRepository, courseFeatureGuard, batchMemberRepository, batchRepository);
        UUID adminMembershipId = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN,
                List.of(new MembershipClaim(adminMembershipId, academyId, "Kalakshetra",
                        Role.ACADEMY_ADMIN, Set.of(), Set.of(courseId))),
                adminMembershipId));
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
        memberships.clear();
        users.clear();
        courseMaps.clear();
        batchMembers.clear();
    }

    /** Adds a student to the batch and enrols them in the course at the given fee. */
    private UUID student(String name, String agreedFee) {
        UUID membershipId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        memberships.add(AcademyMembership.builder().id(membershipId).userId(userId).academyId(academyId)
                .roleType(Role.STUDENT).status(MembershipStatus.ACTIVE).build());
        User u = new User();
        u.setId(userId);
        u.setFullName(name);
        users.add(u);
        courseMaps.add(CourseMap.builder().membershipId(membershipId).courseId(courseId)
                .agreedFee(new BigDecimal(agreedFee)).active(true).build());
        batchMembers.add(BatchMember.builder().batchId(batchId).membershipId(membershipId).build());
        return membershipId;
    }

    /** In the batch but NOT enrolled in this course - the Temporary-batch case. */
    private void batchOnlyStudent(String name) {
        UUID membershipId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        memberships.add(AcademyMembership.builder().id(membershipId).userId(userId).academyId(academyId)
                .roleType(Role.STUDENT).status(MembershipStatus.ACTIVE).build());
        User u = new User();
        u.setId(userId);
        u.setFullName(name);
        users.add(u);
        batchMembers.add(BatchMember.builder().batchId(batchId).membershipId(membershipId).build());
    }

    private FeeTransaction payment(UUID membershipId, String amount, FeeMode mode, int secondsAgo) {
        return FeeTransaction.builder()
                .id(UUID.randomUUID()).academyId(academyId).category(FeeCategory.REGULAR)
                .membershipId(membershipId).courseId(courseId).period(PERIOD)
                .amountPaid(new BigDecimal(amount)).mode(mode)
                .occurredOn(LocalDate.now())
                .createdAt(Instant.now().minusSeconds(secondsAgo))
                .build();
    }

    private void wire(List<FeeTransaction> transactions, List<FeeSlip> slips) {
        when(batchMemberRepository.findByBatchId(batchId)).thenReturn(batchMembers);
        lenient().when(courseMapRepository.findByCourseId(courseId)).thenReturn(courseMaps);
        lenient().when(membershipRepository.findAllById(anyIterable())).thenAnswer(inv -> {
            Iterable<?> ids = inv.getArgument(0);
            List<UUID> wanted = new ArrayList<>();
            ids.forEach(i -> wanted.add((UUID) i));
            return memberships.stream().filter(m -> wanted.contains(m.getId())).toList();
        });
        lenient().when(userRepository.findAllById(anyIterable())).thenAnswer(inv -> {
            Iterable<?> ids = inv.getArgument(0);
            List<UUID> wanted = new ArrayList<>();
            ids.forEach(i -> wanted.add((UUID) i));
            return users.stream().filter(u -> wanted.contains(u.getId())).toList();
        });
        lenient().when(feeSlipRepository.findByCourseIdAndPeriod(courseId, PERIOD)).thenReturn(slips);
        lenient().when(feeTransactionRepository.findByCourseIdAndPeriod(courseId, PERIOD)).thenReturn(transactions);
    }

    @Test
    void statusIsDerivedFromWhatTheLedgerHolds() {
        UUID unpaid = student("Anita", "1000");
        UUID partial = student("Bhavna", "1000");
        UUID cashPaid = student("Chitra", "1000");
        UUID gatewayPaid = student("Divya", "1000");

        wire(List.of(
                payment(partial, "400", FeeMode.CASH, 60),
                payment(cashPaid, "1000", FeeMode.CASH, 60),
                payment(gatewayPaid, "1000", FeeMode.GATEWAY, 60)
        ), List.of());

        var roster = feesService.roster(courseId, batchId, PERIOD);

        assertThat(roster.entries()).hasSize(4);
        assertThat(statusOf(roster, unpaid)).isEqualTo(PaymentStatus.NOT_PAID);
        assertThat(statusOf(roster, partial)).isEqualTo(PaymentStatus.PARTIAL);
        // The badge distinguishes how the money arrived, so an admin knows whether to expect it in
        // the cash box or on the gateway statement.
        assertThat(statusOf(roster, cashPaid)).isEqualTo(PaymentStatus.PAID_MANUAL);
        assertThat(statusOf(roster, gatewayPaid)).isEqualTo(PaymentStatus.PAID_GATEWAY);
    }

    @Test
    void unpaidPastTheBillingPeriodReadsAsDue() {
        // "Due" is not a stored flag - it is NOT_PAID that has run out of road, so it changes on
        // its own as the date passes rather than needing a job to update rows.
        UUID overdue = student("Anita", "1000");
        FeeSlip slip = FeeSlip.builder().id(UUID.randomUUID()).membershipId(overdue).courseId(courseId)
                .period(PERIOD).amountDue(new BigDecimal("1000"))
                .billingPeriodStart(LocalDate.now().minusDays(40))
                .billingPeriodEnd(LocalDate.now().minusDays(5))
                .status(FeeSlipStatus.OPEN).build();
        wire(List.of(), List.of(slip));

        assertThat(statusOf(feesService.roster(courseId, batchId, PERIOD), overdue))
                .isEqualTo(PaymentStatus.DUE);
    }

    @Test
    void reversingAPaymentPutsTheStudentBackToUnpaid() {
        // The whole point of the signed ledger: the same SUM answers before and after an undo,
        // with no stored balance to correct.
        UUID membershipId = student("Anita", "1000");
        FeeTransaction paid = payment(membershipId, "1000", FeeMode.CASH, 120);
        FeeTransaction reversal = payment(membershipId, "-1000", FeeMode.CASH, 60);
        reversal.setReversalOfTransactionId(paid.getId());

        wire(List.of(paid, reversal), List.of());

        var entry = entryOf(feesService.roster(courseId, batchId, PERIOD), membershipId);
        assertThat(entry.totalPaid()).isEqualByComparingTo("0");
        assertThat(entry.balance()).isEqualByComparingTo("1000");
        assertThat(entry.status()).isEqualTo(PaymentStatus.NOT_PAID);
        // Nothing left to undo - the UI hides the action rather than offering one the DB refuses.
        assertThat(entry.lastPaymentId()).isNull();
    }

    @Test
    void undoTargetsTheMostRecentPaymentThatIsNotAlreadyReversed() {
        UUID membershipId = student("Anita", "1000");
        FeeTransaction first = payment(membershipId, "400", FeeMode.CASH, 300);
        FeeTransaction second = payment(membershipId, "600", FeeMode.CASH, 200);
        FeeTransaction reversalOfSecond = payment(membershipId, "-600", FeeMode.CASH, 100);
        reversalOfSecond.setReversalOfTransactionId(second.getId());

        wire(List.of(first, second, reversalOfSecond), List.of());

        var entry = entryOf(feesService.roster(courseId, batchId, PERIOD), membershipId);
        assertThat(entry.totalPaid()).isEqualByComparingTo("400");
        assertThat(entry.status()).isEqualTo(PaymentStatus.PARTIAL);
        // Not `second` (already reversed) and not the reversal itself.
        assertThat(entry.lastPaymentId()).isEqualTo(first.getId());
    }

    @Test
    void aStudentInTheBatchButNotEnrolledInTheCourseIsNotShownOwingMoney() {
        // A Temporary batch deliberately pulls students across several Regular batches. Someone in
        // the batch without an enrolment has no fee for this course at all.
        UUID enrolled = student("Anita", "1000");
        batchOnlyStudent("Visiting Vidya");
        wire(List.of(), List.of());

        var roster = feesService.roster(courseId, batchId, PERIOD);

        assertThat(roster.entries()).hasSize(1);
        assertThat(roster.entries().get(0).membershipId()).isEqualTo(enrolled);
        assertThat(roster.entries()).noneMatch(e -> e.studentName().equals("Visiting Vidya"));
    }

    @Test
    void totalsAreComputedOverTheSameRowsThatAreReturned() {
        // The progress bar and the list read from one response, so they cannot disagree.
        student("Anita", "1000");
        UUID paidStudent = student("Bhavna", "1000");
        wire(List.of(payment(paidStudent, "1000", FeeMode.CASH, 60)), List.of());

        var roster = feesService.roster(courseId, batchId, PERIOD);

        assertThat(roster.studentCount()).isEqualTo(2);
        assertThat(roster.paidCount()).isEqualTo(1);
        assertThat(roster.expected()).isEqualByComparingTo("2000");
        assertThat(roster.collected()).isEqualByComparingTo("1000");
    }

    @Test
    void emptyBatchReturnsAnEmptyRosterRatherThanFailing() {
        when(batchMemberRepository.findByBatchId(batchId)).thenReturn(List.of());

        var roster = feesService.roster(courseId, batchId, PERIOD);

        assertThat(roster.entries()).isEmpty();
        assertThat(roster.expected()).isEqualByComparingTo("0");
    }

    // ---- reversal rules ----

    @Test
    void reversingWritesACompensatingRowAndNeverTouchesTheOriginal() {
        FeeTransaction original = payment(UUID.randomUUID(), "1000", FeeMode.CASH, 60);
        when(feeTransactionRepository.findByIdAndAcademyId(original.getId(), academyId))
                .thenReturn(Optional.of(original));
        when(feeTransactionRepository.existsByReversalOfTransactionId(original.getId())).thenReturn(false);
        when(feeTransactionRepository.saveAndFlush(any(FeeTransaction.class))).thenAnswer(inv -> {
            FeeTransaction tx = inv.getArgument(0);
            tx.setId(UUID.randomUUID());
            return tx;
        });

        feesService.reverseEntry(original.getId(), "entered twice");

        ArgumentCaptor<FeeTransaction> saved = ArgumentCaptor.forClass(FeeTransaction.class);
        verify(feeTransactionRepository).saveAndFlush(saved.capture());
        FeeTransaction reversal = saved.getValue();
        assertThat(reversal.getAmountPaid()).isEqualByComparingTo("-1000");
        assertThat(reversal.getReversalOfTransactionId()).isEqualTo(original.getId());
        assertThat(reversal.getReversalReason()).isEqualTo("entered twice");
        assertThat(reversal.getAcademyId()).isEqualTo(academyId);
        // Dated today, not backdated to the original - filing it under the original's date would
        // make a past day's totals change retroactively.
        assertThat(reversal.getOccurredOn()).isEqualTo(LocalDate.now());
        assertThat(original.getAmountPaid()).isEqualByComparingTo("1000");
    }

    @Test
    void aPaymentCannotBeReversedTwice() {
        FeeTransaction original = payment(UUID.randomUUID(), "1000", FeeMode.CASH, 60);
        when(feeTransactionRepository.findByIdAndAcademyId(original.getId(), academyId))
                .thenReturn(Optional.of(original));
        when(feeTransactionRepository.existsByReversalOfTransactionId(original.getId())).thenReturn(true);

        assertThatThrownBy(() -> feesService.reverseEntry(original.getId(), null))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("already been reversed");
    }

    @Test
    void aReversalCannotItselfBeReversed() {
        // Two rows cancelling a third is not something any screen can render honestly. Paying
        // again is the correct way to express it, since it records a fresh date and mode.
        FeeTransaction reversal = payment(UUID.randomUUID(), "-1000", FeeMode.CASH, 60);
        reversal.setReversalOfTransactionId(UUID.randomUUID());
        when(feeTransactionRepository.findByIdAndAcademyId(reversal.getId(), academyId))
                .thenReturn(Optional.of(reversal));

        assertThatThrownBy(() -> feesService.reverseEntry(reversal.getId(), null))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("itself a reversal");
    }

    @Test
    void anotherAcademysTransactionIsNotFound() {
        // Tenant scoping is by lookup, not by a check after the fact: the id simply does not
        // resolve outside its own academy.
        UUID foreignTxId = UUID.randomUUID();
        when(feeTransactionRepository.findByIdAndAcademyId(foreignTxId, academyId))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> feesService.reverseEntry(foreignTxId, null))
                .isInstanceOf(ResourceNotFoundException.class);
    }

    private PaymentStatus statusOf(com.nest.app.fees.dto.FeeRosterResponse roster, UUID membershipId) {
        return entryOf(roster, membershipId).status();
    }

    private com.nest.app.fees.dto.FeeRosterResponse.FeeRosterEntry entryOf(
            com.nest.app.fees.dto.FeeRosterResponse roster, UUID membershipId) {
        return roster.entries().stream().filter(e -> e.membershipId().equals(membershipId)).findFirst()
                .orElseThrow(() -> new AssertionError("no roster entry for " + membershipId));
    }
}
