package com.nest.app.fees.service;

import com.nest.app.attendance.entity.AttendanceStatus;
import com.nest.app.attendance.repository.AttendanceRepository;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.entity.FeeCycle;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.fees.dto.FeeSlipResponse;
import com.nest.app.fees.entity.FeeSlip;
import com.nest.app.fees.entity.FeeSlipStatus;
import com.nest.app.fees.repository.FeeSlipRepository;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * "if I select the 2nd, for that course, from last 2nd to this 2nd the fees will be checked (per
 * class or hybrid) and the fee slip generated on that 2nd" - reads {@link Course#getFeeModel()}
 * plus held classes/attendance for the period and persists one {@link FeeSlip} per mapped
 * student, on a cadence driven by {@link Course#getFeeCycle()} (monthly/quarterly/yearly - a
 * quarterly course only actually bills every third eligible month, not every month). Generation
 * is idempotent per (membership, course, period): re-running the job or the manual trigger for a
 * period that already has a slip is a no-op for that student, so a mid-cycle manual "generate
 * now" test run never double-bills once the real cron fires.
 */
@Service
public class FeeSlipService {

    private static final Logger log = LoggerFactory.getLogger(FeeSlipService.class);

    private final CourseRepository courseRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final CourseMapRepository courseMapRepository;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final ClassInstanceRepository classInstanceRepository;
    private final AttendanceRepository attendanceRepository;
    private final FeeSlipRepository feeSlipRepository;
    private final FeeTransactionRepository feeTransactionRepository;

    public FeeSlipService(CourseRepository courseRepository, AcademyMembershipRepository membershipRepository,
                           CourseMapRepository courseMapRepository, BatchRepository batchRepository,
                           BatchMemberRepository batchMemberRepository, ClassInstanceRepository classInstanceRepository,
                           AttendanceRepository attendanceRepository, FeeSlipRepository feeSlipRepository,
                           FeeTransactionRepository feeTransactionRepository) {
        this.courseRepository = courseRepository;
        this.membershipRepository = membershipRepository;
        this.courseMapRepository = courseMapRepository;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.classInstanceRepository = classInstanceRepository;
        this.attendanceRepository = attendanceRepository;
        this.feeSlipRepository = feeSlipRepository;
        this.feeTransactionRepository = feeTransactionRepository;
    }

    /** Runs daily with no HTTP request/TenantContext behind it, so it must look across every
     * academy's courses in one query rather than the usual "active academy" scoping - a course
     * billing on the 31st simply has no run in a shorter month, same as a real calendar billing
     * date would. Filtered down to courses actually due THIS month for their own cycle (see
     * {@link #isDueThisMonth}) - a quarterly/yearly course's billing day matching today isn't
     * enough on its own. */
    @Scheduled(cron = "0 0 2 * * *")
    public void generateDueSlipsForToday() {
        LocalDate today = LocalDate.now();
        List<Course> dueCourses = courseRepository.findByBillingDayOfMonthAndStatus(today.getDayOfMonth(), CourseStatus.ACTIVE).stream()
                .filter(c -> isDueThisMonth(c, today))
                .toList();
        for (Course course : dueCourses) {
            try {
                generateSlipsForCourse(course, today);
            } catch (RuntimeException e) {
                log.error("Fee slip generation failed for course {}", course.getId(), e);
            }
        }
    }

    /** Manual trigger for testing/immediate use - same generation logic as the cron, just for
     * one course right now, gated to the caller's own active academy so it can't be used to
     * probe or bill another academy's course. Bypasses {@link #isDueThisMonth} on purpose - an
     * explicit "generate now" click is allowed to catch up a quarterly/yearly course early. */
    @Transactional
    @Auditable(action = "FEE_SLIPS_GENERATED", entityType = "course")
    public List<FeeSlipResponse> generateNow(java.util.UUID courseId) {
        Course course = courseRepository.findById(courseId)
                .orElseThrow(() -> new ResourceNotFoundException("Course not found: " + courseId));
        if (!course.getAcademyId().equals(TenantContext.currentAcademyId())) {
            throw new ForbiddenException("That course does not belong to the active academy");
        }
        return generateSlipsForCourse(course, LocalDate.now()).stream().map(this::toResponse).collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<FeeSlipResponse> historyForStudent(java.util.UUID membershipId) {
        return feeSlipRepository.findByMembershipIdOrderByGeneratedAtDesc(membershipId).stream()
                .map(this::toResponse).collect(Collectors.toList());
    }

    /** MONTHLY bills every eligible month (interval 1 - always true, same as before this cycle
     * concept existed); QUARTERLY every 3rd month and YEARLY every 12th month, counted from the
     * course's own creation month so a course made in March bills quarterly in March/June/etc.
     * TERM_BASED/ONE_TIME never auto-bill - they only make sense as manually recorded fees. */
    private boolean isDueThisMonth(Course course, LocalDate today) {
        int intervalMonths = cycleIntervalMonths(course.getFeeCycle());
        if (intervalMonths <= 0) {
            return false;
        }
        LocalDate anchor = course.getCreatedAt() != null ? course.getCreatedAt().atZone(ZoneOffset.UTC).toLocalDate() : today;
        long monthsSinceAnchor = ChronoUnit.MONTHS.between(anchor.withDayOfMonth(1), today.withDayOfMonth(1));
        return monthsSinceAnchor % intervalMonths == 0;
    }

    private int cycleIntervalMonths(FeeCycle cycle) {
        return switch (cycle) {
            case MONTHLY -> 1;
            case QUARTERLY -> 3;
            case YEARLY -> 12;
            case TERM_BASED, ONE_TIME -> -1;
        };
    }

    /** Not @Transactional itself - the cron entry point calls this via self-invocation (bypasses
     * the Spring proxy, so an annotation here would be a silent no-op there), and the manual
     * generateNow() path already runs inside its own @Transactional boundary. Each FeeSlip save
     * is still atomic on its own (SimpleJpaRepository wraps every call), and the per-membership
     * unique constraint makes re-running this safe either way. */
    protected List<FeeSlip> generateSlipsForCourse(Course course, LocalDate billingDate) {
        int intervalMonths = Math.max(1, cycleIntervalMonths(course.getFeeCycle())); // TERM_BASED/ONE_TIME via generateNow: treat as a single-month snapshot
        LocalDate periodEnd = billingDate;
        LocalDate periodStart = billingDate.minusMonths(intervalMonths);
        String period = billingDate.toString().substring(0, 7);

        Set<java.util.UUID> mappedMembershipIds = courseMapRepository.findByCourseId(course.getId()).stream()
                .map(CourseMap::getMembershipId).collect(Collectors.toSet());
        if (mappedMembershipIds.isEmpty()) {
            return List.of();
        }

        List<AcademyMembership> activeStudents = membershipRepository.findAllById(mappedMembershipIds).stream()
                .filter(m -> m.getRoleType() == Role.STUDENT && m.getStatus() == MembershipStatus.ACTIVE)
                .toList();
        if (activeStudents.isEmpty()) {
            return List.of();
        }

        List<java.util.UUID> batchIds = batchRepository.findByCourseId(course.getId()).stream().map(Batch::getId).toList();
        List<ClassInstance> heldInPeriod = batchIds.isEmpty() ? List.of() :
                classInstanceRepository.findByBatchIdInAndDateBetweenAndStatus(batchIds, periodStart.plusDays(1), periodEnd, ClassInstanceStatus.HELD);

        List<FeeSlip> generated = new ArrayList<>();
        for (AcademyMembership membership : activeStudents) {
            if (feeSlipRepository.findByMembershipIdAndCourseIdAndPeriod(membership.getId(), course.getId(), period).isPresent()) {
                continue;
            }

            Set<java.util.UUID> myBatchIds = batchMemberRepository.findByMembershipId(membership.getId()).stream()
                    .map(BatchMember::getBatchId).filter(batchIds::contains).collect(Collectors.toSet());
            List<ClassInstance> myHeld = heldInPeriod.stream().filter(ci -> myBatchIds.contains(ci.getBatchId())).toList();
            int classesHeld = myHeld.size();

            List<java.util.UUID> myHeldIds = myHeld.stream().map(ClassInstance::getId).toList();
            int classesAttended = myHeldIds.isEmpty() ? 0 : (int) attendanceRepository
                    .findByMembershipIdAndClassInstanceIdIn(membership.getId(), myHeldIds).stream()
                    .filter(a -> a.getStatus() != AttendanceStatus.ABSENT)
                    .count();

            BigDecimal calculatedDue = calculateFee(course, membership.getId(), classesAttended);
            BigDecimal carriedForward = outstandingFromPriorOpenPeriod(membership.getId(), course.getId(), period);
            BigDecimal amountDue = calculatedDue.add(carriedForward);

            FeeSlip slip = feeSlipRepository.save(FeeSlip.builder()
                    .membershipId(membership.getId())
                    .courseId(course.getId())
                    .period(period)
                    .billingPeriodStart(periodStart)
                    .billingPeriodEnd(periodEnd)
                    .amountDue(amountDue)
                    .carriedForwardAmount(carriedForward)
                    .status(FeeSlipStatus.OPEN)
                    .classesHeld(classesHeld)
                    .classesAttended(classesAttended)
                    .generatedAt(Instant.now())
                    .build());
            generated.add(slip);
        }
        return generated;
    }

    /** "The remaining amount... should [carry into] next month's fees" - the immediately
     * preceding period's slip, only if it's still OPEN (an Admin/Trainer who chose "close"
     * instead has already written off whatever was left, so it must never resurface here) and
     * still has money outstanding after every payment recorded against it. */
    private BigDecimal outstandingFromPriorOpenPeriod(java.util.UUID membershipId, java.util.UUID courseId, String currentPeriod) {
        return feeSlipRepository.findFirstByMembershipIdAndCourseIdAndPeriodLessThanOrderByPeriodDesc(membershipId, courseId, currentPeriod)
                .filter(prior -> prior.getStatus() == FeeSlipStatus.OPEN)
                .map(prior -> {
                    BigDecimal paid = feeTransactionRepository.sumPaid(membershipId, courseId, prior.getPeriod());
                    BigDecimal outstanding = prior.getAmountDue().subtract(paid);
                    return outstanding.compareTo(BigDecimal.ZERO) > 0 ? outstanding : BigDecimal.ZERO;
                })
                .orElse(BigDecimal.ZERO);
    }

    /** NEST Course Fee Calculation Spec §2/§3, applied over the billing period just computed. */
    private BigDecimal calculateFee(Course course, java.util.UUID membershipId, int classesAttended) {
        return switch (course.getFeeModel()) {
            case PER_CLASS -> {
                BigDecimal rate = course.getFeePerClass() != null ? course.getFeePerClass() : BigDecimal.ZERO;
                yield rate.multiply(BigDecimal.valueOf(classesAttended));
            }
            case HYBRID -> {
                int threshold = course.getHybridThresholdAttendance() != null ? course.getHybridThresholdAttendance() : 0;
                int percent = classesAttended >= threshold
                        ? course.getHybridFeeAboveThresholdPercent()
                        : (course.getHybridFeeBelowThresholdPercent() != null ? course.getHybridFeeBelowThresholdPercent() : 0);
                BigDecimal base = course.getDefaultFee() != null ? course.getDefaultFee() : BigDecimal.ZERO;
                BigDecimal amount = base.multiply(BigDecimal.valueOf(percent))
                        .divide(BigDecimal.valueOf(100), 2, java.math.RoundingMode.HALF_UP);
                if (course.getHybridMinFeeAmount() != null && amount.compareTo(course.getHybridMinFeeAmount()) < 0) {
                    amount = course.getHybridMinFeeAmount();
                }
                yield amount;
            }
            default -> courseMapRepository.findByMembershipIdAndCourseId(membershipId, course.getId())
                    .map(CourseMap::getAgreedFee)
                    .orElse(course.getDefaultFee() != null ? course.getDefaultFee() : BigDecimal.ZERO);
        };
    }

    private FeeSlipResponse toResponse(FeeSlip s) {
        return new FeeSlipResponse(s.getId(), s.getMembershipId(), s.getCourseId(), s.getPeriod(),
                s.getBillingPeriodStart(), s.getBillingPeriodEnd(), s.getAmountDue(), s.getCarriedForwardAmount(), s.getStatus(),
                s.getClassesHeld(), s.getClassesAttended(), s.getGeneratedAt());
    }
}
