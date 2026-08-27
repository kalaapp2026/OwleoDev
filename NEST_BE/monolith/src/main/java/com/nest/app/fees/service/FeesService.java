package com.nest.app.fees.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.fees.dto.FeeRosterResponse;
import com.nest.app.fees.dto.PaymentStatus;
import com.nest.app.fees.dto.FeeBalanceResponse;
import com.nest.app.fees.dto.FeeTransactionResponse;
import com.nest.app.fees.dto.RecordFeeEntryRequest;
import com.nest.app.fees.entity.FeeMode;
import com.nest.app.fees.entity.FeeCategory;
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
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Objects;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * PRD 3.9. Balance is always derived, never stored: {@code agreedFee - SUM(amountPaid)} for the
 * (membership, course, period) triple, which is what makes "partial payments accumulate against
 * the same billing period" true without any row ever needing to be updated in place. The one
 * exception is a period's OPEN/CLOSED state (see {@link FeeSlip#getStatus()}) - that's the one
 * thing this module does mutate in place, since "close" is explicitly "stop tracking this
 * shortfall going forward", which can't be expressed as just another derived read.
 */
@Service
public class FeesService {

    private final FeeTransactionRepository feeTransactionRepository;
    private final CourseMapRepository courseMapRepository;
    private final FeeSlipRepository feeSlipRepository;
    private final CourseRepository courseRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;
    private final CourseFeatureGuard courseFeatureGuard;
    private final BatchMemberRepository batchMemberRepository;

    public FeesService(FeeTransactionRepository feeTransactionRepository, CourseMapRepository courseMapRepository,
                        FeeSlipRepository feeSlipRepository, CourseRepository courseRepository,
                        AcademyMembershipRepository membershipRepository, UserRepository userRepository,
                        CourseFeatureGuard courseFeatureGuard, BatchMemberRepository batchMemberRepository) {
        this.feeTransactionRepository = feeTransactionRepository;
        this.courseMapRepository = courseMapRepository;
        this.feeSlipRepository = feeSlipRepository;
        this.courseRepository = courseRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.courseFeatureGuard = courseFeatureGuard;
        this.batchMemberRepository = batchMemberRepository;
    }

    /** closePeriod=true ("Close") writes off whatever's left unpaid in this period for good -
     * the next fee slip generated for this membership/course won't carry it forward. Leaving it
     * false/null ("Partial pay", or simply paying the amount due in full) keeps the period OPEN,
     * so an underpayment naturally rolls into the next slip (see FeeSlipService). */
    @Transactional
    @Auditable(action = "FEE_ENTRY_RECORDED", entityType = "fee_transaction")
    public FeeTransactionResponse recordEntry(RecordFeeEntryRequest request) {
        // Per-course enforcement: a Trainer must hold FEES_ENTRY on THIS course, not just some course
        // (the coarse @RequiresFeature only checked the union). Admins bypass inside the guard.
        courseFeatureGuard.assertCourseFeature(request.courseId(), FeatureKey.FEES_ENTRY);
        FeeTransaction tx = FeeTransaction.builder()
                .academyId(TenantContext.currentAcademyId())
                .category(FeeCategory.REGULAR)
                .membershipId(request.membershipId())
                .courseId(request.courseId())
                .period(request.period())
                .amountPaid(request.amountPaid())
                .mode(request.mode())
                .note(request.note())
                .gatewayRef(request.gatewayRef())
                .recordedBy(TenantContext.currentUserId())
                // The date money changed hands, which the caller may backdate for cash taken
                // earlier. Defaults to today rather than being derived from createdAt, so the
                // statement's day grouping never depends on when someone got around to keying it in.
                .occurredOn(request.receivedOn() != null ? request.receivedOn() : LocalDate.now())
                .build();
        // saveAndFlush: see PostService's identical note - @CreationTimestamp isn't populated
        // in-memory until the INSERT runs, which save() alone can defer past this read-back.
        FeeTransactionResponse response = toResponse(feeTransactionRepository.saveAndFlush(tx));

        if (Boolean.TRUE.equals(request.closePeriod())) {
            closePeriod(request.membershipId(), request.courseId(), request.period());
        }
        return response;
    }

    /**
     * Every student in one batch with their fee position for one period, in one response.
     *
     * <p>Deliberately bulk. The obvious implementation - list the batch, then call getBalance per
     * student - is one query per student on the screen an admin opens most often. Everything here
     * is four queries regardless of batch size, then joined in memory.</p>
     *
     * <p>Students are drawn from the batch, then intersected with who is actually enrolled in the
     * course: a Temporary batch pulls students across several Regular batches, and someone in the
     * batch but not enrolled in this course has no fee for it and must not appear owing money.</p>
     */
    @Transactional(readOnly = true)
    public FeeRosterResponse roster(UUID courseId, UUID batchId, String period) {
        courseFeatureGuard.assertCourseFeature(courseId, FeatureKey.FEES_ENTRY);

        List<UUID> batchMemberIds = batchMemberRepository.findByBatchId(batchId).stream()
                .map(BatchMember::getMembershipId).toList();
        if (batchMemberIds.isEmpty()) {
            return new FeeRosterResponse(courseId, batchId, period, 0, 0, BigDecimal.ZERO, BigDecimal.ZERO, List.of());
        }

        // agreedFee per student, and the intersection with "actually enrolled in this course".
        Map<UUID, BigDecimal> agreedFeeByMembership = courseMapRepository.findByCourseId(courseId).stream()
                .filter(CourseMap::isActive)
                .filter(cm -> batchMemberIds.contains(cm.getMembershipId()))
                .collect(Collectors.toMap(CourseMap::getMembershipId,
                        cm -> cm.getAgreedFee() != null ? cm.getAgreedFee() : BigDecimal.ZERO));

        List<AcademyMembership> students = membershipRepository.findAllById(agreedFeeByMembership.keySet()).stream()
                .filter(m -> m.getRoleType() == Role.STUDENT && m.getStatus() == MembershipStatus.ACTIVE)
                .toList();
        Map<UUID, User> usersById = userRepository.findAllById(
                students.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        // A generated slip's amountDue wins over the flat agreed fee - it already includes anything
        // carried forward from an unpaid earlier period.
        Map<UUID, FeeSlip> slipByMembership = feeSlipRepository.findByCourseIdAndPeriod(courseId, period).stream()
                .collect(Collectors.toMap(FeeSlip::getMembershipId, s -> s, (a, b) -> a));

        List<FeeTransaction> transactions = feeTransactionRepository.findByCourseIdAndPeriod(courseId, period);
        Map<UUID, List<FeeTransaction>> txByMembership = transactions.stream()
                .collect(Collectors.groupingBy(FeeTransaction::getMembershipId));
        // Which payments have already been undone, so the roster doesn't offer to undo them twice.
        Set<UUID> reversedIds = transactions.stream()
                .map(FeeTransaction::getReversalOfTransactionId)
                .filter(Objects::nonNull)
                .collect(Collectors.toSet());

        LocalDate today = LocalDate.now();
        List<FeeRosterResponse.FeeRosterEntry> entries = new ArrayList<>();
        BigDecimal expected = BigDecimal.ZERO;
        BigDecimal collected = BigDecimal.ZERO;
        int paidCount = 0;

        for (AcademyMembership membership : students) {
            List<FeeTransaction> rows = txByMembership.getOrDefault(membership.getId(), List.of());
            FeeSlip slip = slipByMembership.get(membership.getId());

            BigDecimal due = slip != null ? slip.getAmountDue()
                    : agreedFeeByMembership.getOrDefault(membership.getId(), BigDecimal.ZERO);
            // Signed sum, so a reversal's negative row takes itself back out with no special case.
            BigDecimal paid = rows.stream().map(FeeTransaction::getAmountPaid)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
            BigDecimal balance = due.subtract(paid);

            // The payment an "undo" would reverse: most recent, not itself a reversal, not already
            // reversed.
            FeeTransaction lastPayment = rows.stream()
                    .filter(t -> !t.isReversal())
                    .filter(t -> !reversedIds.contains(t.getId()))
                    .max(Comparator.comparing(FeeTransaction::getCreatedAt,
                            Comparator.nullsFirst(Comparator.naturalOrder())))
                    .orElse(null);

            boolean closed = slip != null && slip.getStatus() == FeeSlipStatus.CLOSED;
            PaymentStatus status = deriveStatus(closed, due, paid, balance, lastPayment, slip, today);
            if (status == PaymentStatus.PAID_MANUAL || status == PaymentStatus.PAID_GATEWAY
                    || status == PaymentStatus.CLOSED) {
                paidCount++;
            }

            expected = expected.add(due);
            collected = collected.add(paid);

            User user = usersById.get(membership.getUserId());
            entries.add(new FeeRosterResponse.FeeRosterEntry(
                    membership.getId(),
                    user == null ? "Unknown" : user.getFullName(),
                    due, paid, balance, status,
                    lastPayment == null ? null : lastPayment.getId(),
                    lastPayment == null ? null : lastPayment.getOccurredOn(),
                    lastPayment == null ? null : lastPayment.getMode()));
        }

        // Alphabetical: an admin works down a printed or spoken list of names, not a list of ids.
        entries.sort(Comparator.comparing(FeeRosterResponse.FeeRosterEntry::studentName,
                String.CASE_INSENSITIVE_ORDER));

        return new FeeRosterResponse(courseId, batchId, period, entries.size(), paidCount,
                expected, collected, entries);
    }

    /**
     * Status is derived, never stored - see {@link PaymentStatus}. "Due" in particular is just
     * NOT_PAID that has run out of road, so it changes on its own as the date passes rather than
     * needing a job to go and update rows.
     */
    private PaymentStatus deriveStatus(boolean closed, BigDecimal due, BigDecimal paid,
                                       BigDecimal balance, FeeTransaction lastPayment,
                                       FeeSlip slip, LocalDate today) {
        if (closed) {
            return PaymentStatus.CLOSED;
        }
        if (balance.compareTo(BigDecimal.ZERO) <= 0 && due.compareTo(BigDecimal.ZERO) > 0) {
            // Which "paid" it is comes from how the money actually arrived, so the badge tells an
            // admin whether to expect it in the cash box or the gateway statement.
            return lastPayment != null && lastPayment.getMode() == FeeMode.GATEWAY
                    ? PaymentStatus.PAID_GATEWAY
                    : PaymentStatus.PAID_MANUAL;
        }
        if (paid.compareTo(BigDecimal.ZERO) > 0) {
            return PaymentStatus.PARTIAL;
        }
        boolean overdue = slip != null && slip.getBillingPeriodEnd() != null
                && slip.getBillingPeriodEnd().isBefore(today);
        return overdue ? PaymentStatus.DUE : PaymentStatus.NOT_PAID;
    }

    /**
     * Undo a payment by posting a compensating row, never by deleting the original.
     *
     * <p>The ledger is append-only (the database enforces it), so "un-mark paid" writes a negative
     * transaction pointing at the one it cancels. The balance is SUM(amountPaid) either way, so it
     * corrects itself with no stored total to keep in step - and the statement still shows that
     * money was taken and later returned, which is what actually happened.</p>
     *
     * <p>Reversing a reversal is refused rather than allowed to net out. Two rows cancelling a
     * third is not something any screen can render honestly, and "pay again" is the correct way to
     * express that, since it records a new date and mode.</p>
     */
    @Transactional
    @Auditable(action = "FEE_ENTRY_REVERSED", entityType = "fee_transaction")
    public FeeTransactionResponse reverseEntry(UUID transactionId, String reason) {
        UUID academyId = TenantContext.currentAcademyId();
        // By id AND academy: a transaction id is client-supplied, and findById alone would let one
        // academy reverse another's payment.
        FeeTransaction original = feeTransactionRepository.findByIdAndAcademyId(transactionId, academyId)
                .orElseThrow(() -> new ResourceNotFoundException("Transaction not found: " + transactionId));

        if (original.isReversal()) {
            throw new ConflictException("This entry is itself a reversal and cannot be reversed. "
                    + "Record a new payment instead.");
        }
        if (original.getCategory() == FeeCategory.REGULAR) {
            courseFeatureGuard.assertCourseFeature(original.getCourseId(), FeatureKey.FEES_ENTRY);
        }
        // Checked here for a clear message; the partial unique index is what actually guarantees it
        // under two concurrent undos, where both would pass this read.
        if (feeTransactionRepository.existsByReversalOfTransactionId(transactionId)) {
            throw new ConflictException("This payment has already been reversed.");
        }

        FeeTransaction reversal = FeeTransaction.builder()
                .academyId(original.getAcademyId())
                .category(original.getCategory())
                .membershipId(original.getMembershipId())
                .courseId(original.getCourseId())
                .period(original.getPeriod())
                .feeTypeId(original.getFeeTypeId())
                .studentFeeId(original.getStudentFeeId())
                .amountPaid(original.getAmountPaid().negate())
                .mode(original.getMode())
                .reversalOfTransactionId(original.getId())
                .reversalReason(reason)
                .recordedBy(TenantContext.currentUserId())
                // Dated today, not backdated to the original. The reversal is a thing that happened
                // now; filing it under the original's date would make a past day's totals change
                // retroactively.
                .occurredOn(LocalDate.now())
                .build();

        return toResponse(feeTransactionRepository.saveAndFlush(reversal));
    }

    /** Marks this (membership, course, period)'s fee slip CLOSED, creating a minimal one first if
     * auto-billing never generated one (a FIXED-fee course with no billingDayOfMonth configured
     * still needs somewhere to record "this period is settled, don't carry it forward"). */
    private void closePeriod(UUID membershipId, UUID courseId, String period) {
        FeeSlip slip = feeSlipRepository.findByMembershipIdAndCourseIdAndPeriod(membershipId, courseId, period)
                .orElseGet(() -> {
                    BigDecimal agreedFee = courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId)
                            .map(CourseMap::getAgreedFee)
                            .orElse(BigDecimal.ZERO);
                    YearMonth ym = YearMonth.parse(period);
                    return FeeSlip.builder()
                            .membershipId(membershipId)
                            .courseId(courseId)
                            .period(period)
                            .billingPeriodStart(ym.atDay(1))
                            .billingPeriodEnd(ym.atEndOfMonth())
                            .amountDue(agreedFee)
                            .carriedForwardAmount(BigDecimal.ZERO)
                            .generatedAt(Instant.now())
                            .build();
                });
        slip.setStatus(FeeSlipStatus.CLOSED);
        feeSlipRepository.save(slip);
    }

    /** A generated {@link FeeSlip} for this (membership, course, period) - the attendance-
     * calculated amount from a PER_CLASS/HYBRID course, already including anything carried
     * forward from an unresolved prior period - takes precedence over the flat
     * CourseMap.agreedFee once one exists, so the Fees screen's balance reflects what was
     * actually billed rather than a stale manually-set number. FIXED-model courses without a
     * slip yet fall back to agreedFee exactly as before this feature existed. */
    @Transactional(readOnly = true)
    public FeeBalanceResponse getBalance(UUID membershipId, UUID courseId, String period) {
        var slip = feeSlipRepository.findByMembershipIdAndCourseIdAndPeriod(membershipId, courseId, period);
        BigDecimal agreedFee = slip.map(FeeSlip::getAmountDue)
                .orElseGet(() -> courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId)
                        .map(CourseMap::getAgreedFee)
                        .orElseThrow(() -> new ResourceNotFoundException("No course enrolment found for this membership/course")));

        BigDecimal totalPaid = feeTransactionRepository.sumPaid(membershipId, courseId, period);
        BigDecimal balance = agreedFee.subtract(totalPaid);
        boolean closed = slip.map(s -> s.getStatus() == FeeSlipStatus.CLOSED).orElse(false);
        return new FeeBalanceResponse(membershipId, courseId, period, agreedFee, totalPaid, balance, closed);
    }

    @Transactional(readOnly = true)
    public List<FeeTransactionResponse> historyForStudent(UUID membershipId) {
        return feeTransactionRepository.findByMembershipIdOrderByCreatedAtDesc(membershipId).stream()
                .map(this::toResponse).collect(Collectors.toList());
    }

    /** Course/batch/month/mode-filtered aggregate for the Fees Dashboard (PRD 3.9.3) - Phase 1
     * ships the course+period slice; full multi-dimension filtering is later polish. */
    @Transactional(readOnly = true)
    public BigDecimal collectedForCourseAndPeriod(UUID courseId, String period) {
        return feeTransactionRepository.findByCourseIdAndPeriod(courseId, period).stream()
                .map(FeeTransaction::getAmountPaid)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    /** The download report: every active Student mapped to this course, what they owe and paid
     * this period, and the course's own fee cycle label - one CSV row per student. */
    @Transactional(readOnly = true)
    public String generateCourseReport(UUID courseId, String period) {
        Course course = courseRepository.findById(courseId)
                .orElseThrow(() -> new ResourceNotFoundException("Course not found: " + courseId));

        List<CourseMap> mappings = courseMapRepository.findByCourseId(courseId);
        Set<UUID> membershipIds = mappings.stream().map(CourseMap::getMembershipId).collect(Collectors.toSet());
        Map<UUID, BigDecimal> agreedFeeByMembership = mappings.stream()
                .collect(Collectors.toMap(CourseMap::getMembershipId, cm -> cm.getAgreedFee() != null ? cm.getAgreedFee() : BigDecimal.ZERO));

        List<AcademyMembership> students = membershipRepository.findAllById(membershipIds).stream()
                .filter(m -> m.getRoleType() == Role.STUDENT && m.getStatus() == MembershipStatus.ACTIVE)
                .sorted((a, b) -> a.getId().compareTo(b.getId()))
                .toList();
        Map<UUID, User> usersById = userRepository.findAllById(
                students.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        StringBuilder csv = new StringBuilder();
        csv.append("Student,Course,Fee Cycle,Period,Amount Due,Amount Paid,Balance,Status\n");
        for (AcademyMembership membership : students) {
            User user = usersById.get(membership.getUserId());
            var slip = feeSlipRepository.findByMembershipIdAndCourseIdAndPeriod(membership.getId(), courseId, period);
            BigDecimal due = slip.map(FeeSlip::getAmountDue)
                    .orElse(agreedFeeByMembership.getOrDefault(membership.getId(), BigDecimal.ZERO));
            BigDecimal paid = feeTransactionRepository.sumPaid(membership.getId(), courseId, period);
            BigDecimal balance = due.subtract(paid);
            boolean closed = slip.map(s -> s.getStatus() == FeeSlipStatus.CLOSED).orElse(false);
            String status = closed ? "Closed"
                    : balance.compareTo(BigDecimal.ZERO) <= 0 ? "Paid"
                    : paid.compareTo(BigDecimal.ZERO) > 0 ? "Partial" : "Due";

            csv.append(csvField(user == null ? "Unknown" : user.getFullName())).append(',')
                    .append(csvField(course.getName())).append(',')
                    .append(course.getFeeCycle()).append(',')
                    .append(period).append(',')
                    .append(due).append(',')
                    .append(paid).append(',')
                    .append(balance).append(',')
                    .append(status).append('\n');
        }
        return csv.toString();
    }

    private String csvField(String value) {
        String escaped = value.replace("\"", "\"\"");
        return "\"" + escaped + "\"";
    }

    private FeeTransactionResponse toResponse(FeeTransaction tx) {
        return new FeeTransactionResponse(tx.getId(), tx.getMembershipId(), tx.getCourseId(), tx.getPeriod(),
                tx.getAmountPaid(), tx.getMode(), tx.getNote(), tx.getRecordedBy(), tx.getGatewayRef(), tx.getCreatedAt());
    }
}
