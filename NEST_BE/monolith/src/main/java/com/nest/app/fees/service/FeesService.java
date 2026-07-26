package com.nest.app.fees.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.fees.dto.FeeBalanceResponse;
import com.nest.app.fees.dto.FeeTransactionResponse;
import com.nest.app.fees.dto.RecordFeeEntryRequest;
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
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.YearMonth;
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

    public FeesService(FeeTransactionRepository feeTransactionRepository, CourseMapRepository courseMapRepository,
                        FeeSlipRepository feeSlipRepository, CourseRepository courseRepository,
                        AcademyMembershipRepository membershipRepository, UserRepository userRepository,
                        CourseFeatureGuard courseFeatureGuard) {
        this.feeTransactionRepository = feeTransactionRepository;
        this.courseMapRepository = courseMapRepository;
        this.feeSlipRepository = feeSlipRepository;
        this.courseRepository = courseRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.courseFeatureGuard = courseFeatureGuard;
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
                .membershipId(request.membershipId())
                .courseId(request.courseId())
                .period(request.period())
                .amountPaid(request.amountPaid())
                .mode(request.mode())
                .note(request.note())
                .gatewayRef(request.gatewayRef())
                .recordedBy(TenantContext.currentUserId())
                .build();
        // saveAndFlush: see PostService's identical note - @CreationTimestamp isn't populated
        // in-memory until the INSERT runs, which save() alone can defer past this read-back.
        FeeTransactionResponse response = toResponse(feeTransactionRepository.saveAndFlush(tx));

        if (Boolean.TRUE.equals(request.closePeriod())) {
            closePeriod(request.membershipId(), request.courseId(), request.period());
        }
        return response;
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
