package com.nest.app.enrolment.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.dto.CourseChangeResponse;
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
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Moves a student from one course to another on a future date.
 *
 * <p>The point is the fee: a Basic student promoted to Advanced is billed Advanced from the NEXT month's
 * slip, while this month's Basic slip - already issued - is left exactly as it is. So scheduling changes
 * nothing; a job applies each due move on its day, flipping the two enrolments and moving the student
 * between batches. Fee slips are generated per (student, course, month) from active enrolments, so from
 * that day the old course stops billing and the new one starts.
 */
@Service
public class CourseChangeService {

    private static final Logger log = LoggerFactory.getLogger(CourseChangeService.class);

    private final StudentCourseChangeRepository changeRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final CourseRepository courseRepository;
    private final CourseMapRepository courseMapRepository;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final CourseFeatureGuard courseFeatureGuard;
    private final TransactionTemplate transactionTemplate;

    public CourseChangeService(StudentCourseChangeRepository changeRepository,
                               AcademyMembershipRepository membershipRepository,
                               CourseRepository courseRepository,
                               CourseMapRepository courseMapRepository,
                               BatchRepository batchRepository,
                               BatchMemberRepository batchMemberRepository,
                               CourseFeatureGuard courseFeatureGuard,
                               PlatformTransactionManager transactionManager) {
        this.changeRepository = changeRepository;
        this.membershipRepository = membershipRepository;
        this.courseRepository = courseRepository;
        this.courseMapRepository = courseMapRepository;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.courseFeatureGuard = courseFeatureGuard;
        this.transactionTemplate = new TransactionTemplate(transactionManager);
    }

    /** The 1st of the month after {@code today} - when a promotion's new fee starts by default. */
    static LocalDate firstOfNextMonth(LocalDate today) {
        return today.withDayOfMonth(1).plusMonths(1);
    }

    @Transactional
    @Auditable(action = "COURSE_CHANGE_SCHEDULED", entityType = "student_course_change")
    public CourseChangeResponse schedule(UUID membershipId, CreateCourseChangeRequest request) {
        UUID academyId = TenantContext.currentAcademyId();
        AcademyMembership student = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Student not found: " + membershipId));
        if (!academyId.equals(student.getAcademyId()) || student.getRoleType() != Role.STUDENT) {
            throw new ResourceNotFoundException("Student not found: " + membershipId);
        }

        UUID from = request.fromCourseId();
        UUID to = request.toCourseId();
        if (from.equals(to)) {
            throw new BadRequestException("Pick a different course to move to.");
        }
        // Moving someone between courses touches both: they leave one's roster and join the other's.
        courseFeatureGuard.assertCourseFeature(from, FeatureKey.STUDENT_REGISTRATION);
        courseFeatureGuard.assertCourseFeature(to, FeatureKey.STUDENT_REGISTRATION);

        Course fromCourse = inAcademy(from, academyId);
        Course toCourse = inAcademy(to, academyId);
        if (toCourse.getStatus() != CourseStatus.ACTIVE) {
            throw new BadRequestException(toCourse.getName() + " is not active, so nobody can move into it.");
        }
        courseMapRepository.findByMembershipIdAndCourseId(membershipId, from)
                .filter(CourseMap::isActive)
                .orElseThrow(() -> new BadRequestException(
                        "This student is not enrolled in " + fromCourse.getName() + "."));

        LocalDate today = LocalDate.now();
        LocalDate effectiveOn = request.effectiveOn() != null ? request.effectiveOn() : firstOfNextMonth(today);
        if (!effectiveOn.isAfter(today)) {
            throw new BadRequestException("The move must start on a future date.");
        }
        if (changeRepository.existsByMembershipIdAndFromCourseIdAndStatus(
                membershipId, from, StudentCourseChange.Status.PENDING)) {
            throw new ConflictException("A move out of " + fromCourse.getName()
                    + " is already scheduled for this student - cancel it first to schedule another.");
        }

        List<UUID> batchIds = request.toBatchIds() == null ? List.of()
                : request.toBatchIds().stream().filter(Objects::nonNull).distinct().toList();
        List<Batch> batches = batchRepository.findAllById(batchIds);
        if (batches.size() != batchIds.size()) {
            throw new ResourceNotFoundException("One or more batches do not exist");
        }
        for (Batch batch : batches) {
            if (!batch.coversCourse(to)) {
                throw new BadRequestException("\"" + batch.getName() + "\" is not a batch of " + toCourse.getName() + ".");
            }
            if (batch.getStatus() != BatchStatus.ACTIVE) {
                throw new BadRequestException("\"" + batch.getName() + "\" is not active.");
            }
        }

        StudentCourseChange saved = changeRepository.save(StudentCourseChange.builder()
                .membershipId(membershipId)
                .fromCourseId(from)
                .toCourseId(to)
                .effectiveOn(effectiveOn)
                .toBatchIds(batchIds.isEmpty() ? null : batchIds.stream().map(UUID::toString).collect(Collectors.joining(",")))
                .createdBy(TenantContext.currentUserId())
                .build());
        return toResponses(List.of(saved)).get(0);
    }

    /** A student's scheduled moves that the caller can act on (they hold the permission on one of the courses). */
    @Transactional(readOnly = true)
    public List<CourseChangeResponse> pendingFor(UUID membershipId) {
        AcademyMembership student = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Student not found: " + membershipId));
        if (!TenantContext.currentAcademyId().equals(student.getAcademyId())) {
            throw new ResourceNotFoundException("Student not found: " + membershipId);
        }
        List<StudentCourseChange> mine = changeRepository
                .findByMembershipIdAndStatusOrderByEffectiveOnAsc(membershipId, StudentCourseChange.Status.PENDING).stream()
                .filter(c -> courseFeatureGuard.hasCourseFeature(c.getFromCourseId(), FeatureKey.STUDENT_REGISTRATION)
                        || courseFeatureGuard.hasCourseFeature(c.getToCourseId(), FeatureKey.STUDENT_REGISTRATION))
                .toList();
        return toResponses(mine);
    }

    @Transactional
    @Auditable(action = "COURSE_CHANGE_CANCELLED", entityType = "student_course_change")
    public void cancel(UUID changeId) {
        StudentCourseChange change = changeRepository.findById(changeId)
                .orElseThrow(() -> new ResourceNotFoundException("Course change not found: " + changeId));
        AcademyMembership student = membershipRepository.findById(change.getMembershipId())
                .orElseThrow(() -> new ResourceNotFoundException("Course change not found: " + changeId));
        if (!TenantContext.currentAcademyId().equals(student.getAcademyId())) {
            throw new ResourceNotFoundException("Course change not found: " + changeId);
        }
        if (!courseFeatureGuard.hasCourseFeature(change.getFromCourseId(), FeatureKey.STUDENT_REGISTRATION)
                && !courseFeatureGuard.hasCourseFeature(change.getToCourseId(), FeatureKey.STUDENT_REGISTRATION)) {
            throw new ForbiddenException("You don't have the 'STUDENT_REGISTRATION' permission for these courses");
        }
        if (change.getStatus() != StudentCourseChange.Status.PENDING) {
            throw new ConflictException("That move has already been " + change.getStatus().name().toLowerCase() + ".");
        }
        change.setStatus(StudentCourseChange.Status.CANCELLED);
        changeRepository.save(change);
    }

    /**
     * Applies every pending move due on or before {@code today}. Idempotent - an applied move is no longer
     * pending - so running it again, or late after a missed night, is safe. Each move is its own
     * transaction: one that cannot be applied is logged and left pending rather than blocking the rest.
     *
     * @return how many were applied
     */
    public int applyDue(LocalDate today) {
        int applied = 0;
        for (StudentCourseChange due : changeRepository.findByStatusAndEffectiveOnLessThanEqual(
                StudentCourseChange.Status.PENDING, today)) {
            try {
                transactionTemplate.executeWithoutResult(status -> applyOne(due.getId()));
                applied++;
            } catch (RuntimeException e) {
                log.error("Could not apply course change {}", due.getId(), e);
            }
        }
        return applied;
    }

    private void applyOne(UUID changeId) {
        StudentCourseChange change = changeRepository.findById(changeId).orElse(null);
        if (change == null || change.getStatus() != StudentCourseChange.Status.PENDING) {
            return;
        }
        UUID member = change.getMembershipId();
        Course toCourse = courseRepository.findById(change.getToCourseId()).orElse(null);
        if (toCourse == null) {
            throw new IllegalStateException("Target course is gone: " + change.getToCourseId());
        }

        // The new course: enrol (or switch an old, deactivated enrolment back on) at its default fee.
        CourseMap into = courseMapRepository.findByMembershipIdAndCourseId(member, change.getToCourseId())
                .orElseGet(() -> CourseMap.builder().membershipId(member).courseId(change.getToCourseId())
                        .agreedFee(toCourse.getDefaultFee()).build());
        into.setActive(true);
        if (into.getAgreedFee() == null) {
            into.setAgreedFee(toCourse.getDefaultFee());
        }
        courseMapRepository.save(into);

        // The old course stops: no more slips, off its rosters. The slip already issued is untouched.
        courseMapRepository.findByMembershipIdAndCourseId(member, change.getFromCourseId()).ifPresent(out -> {
            out.setActive(false);
            courseMapRepository.save(out);
        });

        // Batches: out of the Regular ones that only taught the old course, into the chosen new ones.
        List<BatchMember> seats = batchMemberRepository.findByMembershipId(member);
        Map<UUID, Batch> batchesById = batchRepository
                .findAllById(seats.stream().map(BatchMember::getBatchId).collect(Collectors.toSet())).stream()
                .collect(Collectors.toMap(Batch::getId, b -> b));
        for (BatchMember seat : seats) {
            Batch batch = batchesById.get(seat.getBatchId());
            if (batch != null && batch.getBatchType() == BatchType.REGULAR
                    && batch.coversCourse(change.getFromCourseId()) && !batch.coversCourse(change.getToCourseId())) {
                batchMemberRepository.deleteByBatchIdAndMembershipId(batch.getId(), member);
            }
        }
        for (UUID batchId : parseBatchIds(change.getToBatchIds())) {
            Batch batch = batchRepository.findById(batchId).orElse(null);
            if (batch == null || batchMemberRepository.existsByBatchIdAndMembershipId(batchId, member)) {
                continue;
            }
            if (batch.getBatchType() == BatchType.REGULAR && inAnotherRegularBatchFor(member, batch)) {
                // Leaves the student where they are rather than failing the whole move; an admin can place them.
                log.warn("Course change {}: student {} is already in a Regular batch for {}, not adding to {}",
                        changeId, member, change.getToCourseId(), batchId);
                continue;
            }
            batchMemberRepository.save(BatchMember.builder().batchId(batchId).membershipId(member).build());
        }

        change.setStatus(StudentCourseChange.Status.APPLIED);
        change.setAppliedAt(Instant.now());
        changeRepository.save(change);
    }

    private boolean inAnotherRegularBatchFor(UUID member, Batch target) {
        Set<UUID> mine = batchMemberRepository.findByMembershipId(member).stream()
                .map(BatchMember::getBatchId).collect(Collectors.toSet());
        return batchRepository.findAllById(mine).stream()
                .anyMatch(b -> b.getBatchType() == BatchType.REGULAR && !b.getId().equals(target.getId())
                        && b.allCourseIds().stream().anyMatch(target::coversCourse));
    }

    private static List<UUID> parseBatchIds(String csv) {
        if (csv == null || csv.isBlank()) {
            return List.of();
        }
        return Arrays.stream(csv.split(",")).map(String::trim).filter(s -> !s.isEmpty()).map(UUID::fromString).toList();
    }

    private Course inAcademy(UUID courseId, UUID academyId) {
        Course course = courseRepository.findById(courseId)
                .orElseThrow(() -> new ResourceNotFoundException("Course not found: " + courseId));
        if (!academyId.equals(course.getAcademyId())) {
            throw new ResourceNotFoundException("Course not found: " + courseId);
        }
        return course;
    }

    private List<CourseChangeResponse> toResponses(List<StudentCourseChange> changes) {
        if (changes.isEmpty()) {
            return List.of();
        }
        Set<UUID> courseIds = changes.stream().flatMap(c -> java.util.stream.Stream.of(c.getFromCourseId(), c.getToCourseId()))
                .collect(Collectors.toSet());
        Map<UUID, String> courseNames = courseRepository.findAllById(courseIds).stream()
                .collect(Collectors.toMap(Course::getId, Course::getName, (a, b) -> a));
        Set<UUID> batchIds = changes.stream().flatMap(c -> parseBatchIds(c.getToBatchIds()).stream()).collect(Collectors.toSet());
        Map<UUID, String> batchNames = batchIds.isEmpty() ? Map.of()
                : batchRepository.findAllById(batchIds).stream().collect(Collectors.toMap(Batch::getId, Batch::getName, (a, b) -> a));

        List<CourseChangeResponse> out = new ArrayList<>();
        for (StudentCourseChange c : changes) {
            out.add(new CourseChangeResponse(c.getId(), c.getMembershipId(),
                    c.getFromCourseId(), courseNames.getOrDefault(c.getFromCourseId(), "Course"),
                    c.getToCourseId(), courseNames.getOrDefault(c.getToCourseId(), "Course"),
                    c.getEffectiveOn(), c.getStatus().name(),
                    parseBatchIds(c.getToBatchIds()).stream().map(id -> batchNames.getOrDefault(id, "Batch")).toList()));
        }
        return out;
    }
}
