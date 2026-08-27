package com.nest.app.fees.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchStatus;
import com.nest.app.enrolment.entity.BatchType;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.fees.dto.CreateFeeTypeRequest;
import com.nest.app.fees.dto.PaymentStatus;
import com.nest.app.fees.dto.RecordOtherFeeRequest;
import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.entity.FeeMode;
import com.nest.app.fees.entity.FeeTransaction;
import com.nest.app.fees.entity.FeeType;
import com.nest.app.fees.entity.FeeTypeBatch;
import com.nest.app.fees.entity.StudentFee;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.fees.repository.FeeTypeBatchRepository;
import com.nest.app.fees.repository.FeeTypeRepository;
import com.nest.app.fees.repository.StudentFeeRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
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

/** Other Fees: tenant scoping on client-supplied ids, and what a payment may be posted against. */
@ExtendWith(MockitoExtension.class)
class OtherFeesServiceTest {

    @Mock private FeeTypeRepository feeTypeRepository;
    @Mock private FeeTypeBatchRepository feeTypeBatchRepository;
    @Mock private StudentFeeRepository studentFeeRepository;
    @Mock private FeeTransactionRepository feeTransactionRepository;
    @Mock private BatchRepository batchRepository;
    @Mock private BatchMemberRepository batchMemberRepository;
    @Mock private CourseRepository courseRepository;
    @Mock private AcademyMembershipRepository membershipRepository;
    @Mock private UserRepository userRepository;

    private OtherFeesService service;

    private final UUID academyId = UUID.randomUUID();
    private final UUID otherAcademyId = UUID.randomUUID();
    private final UUID courseId = UUID.randomUUID();
    private final UUID batchId = UUID.randomUUID();
    private final UUID feeTypeId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new OtherFeesService(feeTypeRepository, feeTypeBatchRepository, studentFeeRepository,
                feeTransactionRepository, batchRepository, batchMemberRepository, courseRepository,
                membershipRepository, userRepository);
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

    private FeeType feeType(String amount, LocalDate dueDate) {
        return FeeType.builder().id(feeTypeId).academyId(academyId).name("Costume Fee")
                .amount(new BigDecimal(amount)).dueDate(dueDate).active(true).build();
    }

    private Batch batch(UUID id, UUID course) {
        return Batch.builder().id(id).courseId(course).name("Batch A")
                .batchType(BatchType.REGULAR).status(BatchStatus.ACTIVE).build();
    }

    private Course course(UUID id, UUID academy) {
        Course c = new Course();
        c.setId(id);
        c.setName("Guitar Beginner");
        c.setAcademyId(academy);
        return c;
    }

    // ---- creating a fee type ----

    @Test
    void aFeeTypeCannotBeBoundToAnotherAcademysBatch() {
        // Batch ids come from a client. Without this an academy could bind its fee type to another
        // academy's batch and start charging their students.
        when(feeTypeRepository.existsByAcademyIdAndNameIgnoreCase(academyId, "Costume Fee"))
                .thenReturn(false);
        // The batch resolves - it genuinely exists. What makes it unusable is that its course
        // belongs to another academy, which is the check under test. Without this stub the call
        // fails earlier at "batch not found" and the test passes while proving nothing.
        when(batchRepository.findAllById(List.of(batchId))).thenReturn(List.of(batch(batchId, courseId)));
        when(courseRepository.findAllById(Set.of(courseId)))
                .thenReturn(List.of(course(courseId, otherAcademyId)));

        assertThatThrownBy(() -> service.createFeeType(new CreateFeeTypeRequest(
                "Costume Fee", new BigDecimal("750"), List.of(batchId), null, null)))
                .isInstanceOf(ResourceNotFoundException.class);

        verify(feeTypeRepository, org.mockito.Mockito.never()).save(any());
    }

    @Test
    void twoFeeTypesInOneAcademyCannotShareAName() {
        when(feeTypeRepository.existsByAcademyIdAndNameIgnoreCase(academyId, "Costume Fee"))
                .thenReturn(true);

        assertThatThrownBy(() -> service.createFeeType(new CreateFeeTypeRequest(
                "Costume Fee", new BigDecimal("750"), List.of(batchId), null, null)))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("already exists");
    }

    // ---- recording a payment ----

    @Test
    void aPaymentMustTargetExactlyOneKindOfFee() {
        // Rejected here rather than left to the database's check constraint, so the caller gets a
        // sentence instead of a constraint name.
        assertThatThrownBy(() -> service.recordPayment(new RecordOtherFeeRequest(
                UUID.randomUUID(), feeTypeId, UUID.randomUUID(), new BigDecimal("100"),
                FeeMode.CASH, null, null, null)))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("exactly one");

        assertThatThrownBy(() -> service.recordPayment(new RecordOtherFeeRequest(
                UUID.randomUUID(), null, null, new BigDecimal("100"),
                FeeMode.CASH, null, null, null)))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("exactly one");
    }

    @Test
    void anOtherPaymentCarriesNoCourseOrPeriod() {
        // The database's category check enforces this too; getting it wrong here would fail the
        // insert rather than write a malformed row, but the shape belongs in the service.
        UUID membershipId = UUID.randomUUID();
        when(feeTypeRepository.findByIdAndAcademyId(feeTypeId, academyId))
                .thenReturn(Optional.of(feeType("750", null)));
        when(feeTransactionRepository.saveAndFlush(any(FeeTransaction.class))).thenAnswer(inv -> {
            FeeTransaction tx = inv.getArgument(0);
            tx.setId(UUID.randomUUID());
            return tx;
        });

        service.recordPayment(new RecordOtherFeeRequest(membershipId, feeTypeId, null,
                new BigDecimal("750"), FeeMode.UPI, "upi-123", null, LocalDate.of(2026, 8, 4)));

        ArgumentCaptor<FeeTransaction> saved = ArgumentCaptor.forClass(FeeTransaction.class);
        verify(feeTransactionRepository).saveAndFlush(saved.capture());
        FeeTransaction tx = saved.getValue();
        assertThat(tx.getCategory()).isEqualTo(FeeCategory.OTHER);
        assertThat(tx.getCourseId()).isNull();
        assertThat(tx.getPeriod()).isNull();
        assertThat(tx.getFeeTypeId()).isEqualTo(feeTypeId);
        assertThat(tx.getStudentFeeId()).isNull();
        assertThat(tx.getAcademyId()).isEqualTo(academyId);
        // Backdated as asked, so cash taken on Saturday files under Saturday.
        assertThat(tx.getOccurredOn()).isEqualTo(LocalDate.of(2026, 8, 4));
    }

    @Test
    void cannotPayAnotherAcademysFeeType() {
        when(feeTypeRepository.findByIdAndAcademyId(feeTypeId, academyId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.recordPayment(new RecordOtherFeeRequest(
                UUID.randomUUID(), feeTypeId, null, new BigDecimal("750"),
                FeeMode.CASH, null, null, null)))
                .isInstanceOf(ResourceNotFoundException.class);
    }

    @Test
    void cannotPayAStudentFeeThatBelongsToSomeoneElse() {
        // A one-off fee is keyed only by student, so mixing them up would charge the wrong family.
        UUID studentFeeId = UUID.randomUUID();
        when(studentFeeRepository.findByIdAndAcademyId(studentFeeId, academyId)).thenReturn(
                Optional.of(StudentFee.builder().id(studentFeeId).academyId(academyId)
                        .membershipId(UUID.randomUUID()).name("Extra costume")
                        .amount(new BigDecimal("350")).build()));

        assertThatThrownBy(() -> service.recordPayment(new RecordOtherFeeRequest(
                UUID.randomUUID(), null, studentFeeId, new BigDecimal("350"),
                FeeMode.CASH, null, null, null)))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("different student");
    }

    // ---- the roster ----

    @Test
    void aFeeTypeCannotBeCollectedFromAnUnboundBatch() {
        // Showing a roster for a batch the fee was never bound to would invite collecting a charge
        // those students were never billed.
        when(feeTypeRepository.findByIdAndAcademyId(feeTypeId, academyId))
                .thenReturn(Optional.of(feeType("750", null)));
        when(batchRepository.findById(batchId)).thenReturn(Optional.of(batch(batchId, courseId)));
        when(courseRepository.findAllById(Set.of(courseId)))
                .thenReturn(List.of(course(courseId, academyId)));
        when(feeTypeBatchRepository.findByFeeTypeId(feeTypeId)).thenReturn(List.of(
                FeeTypeBatch.builder().feeTypeId(feeTypeId).batchId(UUID.randomUUID()).build()));

        assertThatThrownBy(() -> service.roster(feeTypeId, batchId))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("does not apply to this batch");
    }

    @Test
    void everyoneOwesTheSameAmountAndStatusFollowsTheLedger() {
        UUID paidStudent = UUID.randomUUID();
        UUID unpaidStudent = UUID.randomUUID();
        wireRoster(List.of(paidStudent, unpaidStudent), feeType("750", null), List.of(
                otherPayment(paidStudent, "750", FeeMode.CASH)));

        var roster = service.roster(feeTypeId, batchId);

        assertThat(roster.studentCount()).isEqualTo(2);
        assertThat(roster.paidCount()).isEqualTo(1);
        // A costume costs what it costs - there is no per-student agreed figure here.
        assertThat(roster.expected()).isEqualByComparingTo("1500");
        assertThat(roster.collected()).isEqualByComparingTo("750");
        assertThat(entryFor(roster, paidStudent).status()).isEqualTo(PaymentStatus.PAID_MANUAL);
        assertThat(entryFor(roster, unpaidStudent).status()).isEqualTo(PaymentStatus.NOT_PAID);
    }

    @Test
    void unpaidPastTheLastDateToPayReadsAsDue() {
        UUID student = UUID.randomUUID();
        wireRoster(List.of(student), feeType("750", LocalDate.now().minusDays(2)), List.of());

        assertThat(entryFor(service.roster(feeTypeId, batchId), student).status())
                .isEqualTo(PaymentStatus.DUE);
    }

    @Test
    void aReversedPaymentPutsTheStudentBackToUnpaid() {
        UUID student = UUID.randomUUID();
        FeeTransaction paid = otherPayment(student, "750", FeeMode.CASH);
        FeeTransaction reversal = otherPayment(student, "-750", FeeMode.CASH);
        reversal.setReversalOfTransactionId(paid.getId());
        wireRoster(List.of(student), feeType("750", null), List.of(paid, reversal));

        var entry = entryFor(service.roster(feeTypeId, batchId), student);
        assertThat(entry.totalPaid()).isEqualByComparingTo("0");
        assertThat(entry.status()).isEqualTo(PaymentStatus.NOT_PAID);
        assertThat(entry.lastPaymentId()).isNull();
    }

    private FeeTransaction otherPayment(UUID membershipId, String amount, FeeMode mode) {
        return FeeTransaction.builder()
                .id(UUID.randomUUID()).academyId(academyId).category(FeeCategory.OTHER)
                .membershipId(membershipId).feeTypeId(feeTypeId)
                .amountPaid(new BigDecimal(amount)).mode(mode)
                .occurredOn(LocalDate.now()).createdAt(Instant.now())
                .build();
    }

    private void wireRoster(List<UUID> studentIds, FeeType type, List<FeeTransaction> transactions) {
        when(feeTypeRepository.findByIdAndAcademyId(feeTypeId, academyId)).thenReturn(Optional.of(type));
        when(batchRepository.findById(batchId)).thenReturn(Optional.of(batch(batchId, courseId)));
        when(courseRepository.findAllById(Set.of(courseId)))
                .thenReturn(List.of(course(courseId, academyId)));
        when(feeTypeBatchRepository.findByFeeTypeId(feeTypeId)).thenReturn(List.of(
                FeeTypeBatch.builder().feeTypeId(feeTypeId).batchId(batchId).build()));
        when(batchMemberRepository.findByBatchId(batchId)).thenReturn(
                studentIds.stream().map(id -> BatchMember.builder().batchId(batchId)
                        .membershipId(id).build()).toList());

        List<AcademyMembership> memberships = new ArrayList<>();
        List<User> users = new ArrayList<>();
        for (UUID id : studentIds) {
            UUID userId = UUID.randomUUID();
            memberships.add(AcademyMembership.builder().id(id).userId(userId).academyId(academyId)
                    .roleType(Role.STUDENT).status(MembershipStatus.ACTIVE).build());
            User u = new User();
            u.setId(userId);
            u.setFullName("Student " + users.size());
            users.add(u);
        }
        when(membershipRepository.findAllById(anyIterable())).thenReturn(memberships);
        lenient().when(userRepository.findAllById(anyIterable())).thenReturn(users);
        when(feeTransactionRepository.findByFeeTypeId(feeTypeId)).thenReturn(transactions);
    }

    private com.nest.app.fees.dto.FeeRosterResponse.FeeRosterEntry entryFor(
            com.nest.app.fees.dto.FeeRosterResponse roster, UUID membershipId) {
        return roster.entries().stream().filter(e -> e.membershipId().equals(membershipId))
                .findFirst().orElseThrow(() -> new AssertionError("no entry for " + membershipId));
    }
}
