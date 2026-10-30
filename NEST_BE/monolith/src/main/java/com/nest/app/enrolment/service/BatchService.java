package com.nest.app.enrolment.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.curriculum.service.StudyMaterialService;
import com.nest.app.enrolment.dto.BatchMemberSummaryResponse;
import com.nest.app.enrolment.dto.BatchResponse;
import com.nest.app.enrolment.dto.BatchRosterResponse;
import com.nest.app.enrolment.dto.CreateBatchRequest;
import com.nest.app.enrolment.dto.UpdateBatchRequest;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchStatus;
import com.nest.app.enrolment.entity.BatchTrainer;
import com.nest.app.enrolment.entity.BatchType;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.enrolment.repository.BatchTrainerRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.app.scheduling.repository.ScheduleRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/** PRD 3.6. */
@Service
public class BatchService {

    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final BatchTrainerRepository batchTrainerRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;
    private final CourseRepository courseRepository;
    private final ScheduleRepository scheduleRepository;
    private final ClassInstanceRepository classInstanceRepository;
    private final StudyMaterialService studyMaterialService;
    private final CourseFeatureGuard courseFeatureGuard;
    private final StudentBatchCourses studentCourses;

    public BatchService(BatchRepository batchRepository, BatchMemberRepository batchMemberRepository,
                         BatchTrainerRepository batchTrainerRepository,
                         AcademyMembershipRepository membershipRepository, UserRepository userRepository,
                         CourseRepository courseRepository,
                         ScheduleRepository scheduleRepository, ClassInstanceRepository classInstanceRepository,
                         StudyMaterialService studyMaterialService,
                         CourseFeatureGuard courseFeatureGuard, StudentBatchCourses studentCourses) {
        this.studentCourses = studentCourses;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.batchTrainerRepository = batchTrainerRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.courseRepository = courseRepository;
        this.scheduleRepository = scheduleRepository;
        this.classInstanceRepository = classInstanceRepository;
        this.studyMaterialService = studyMaterialService;
        this.courseFeatureGuard = courseFeatureGuard;
    }

    @Transactional
    @Auditable(action = "BATCH_CREATED", entityType = "batch")
    public BatchResponse create(CreateBatchRequest request) {
        List<UUID> courseIds = resolveCourseIds(request.courseIds(), request.courseId());
        assertCoursesInActiveAcademy(courseIds);
        // Per-course enforcement: a Trainer must hold BATCH_CREATION on EVERY course the batch spans
        // (Admins bypass) - a trainer cannot build a class that contains a course they were never given.
        courseFeatureGuard.assertAllCourses(courseIds, FeatureKey.BATCH_CREATION);

        List<UUID> trainerIds = resolveTrainerIds(request.trainerMembershipIds(), request.trainerMembershipId());
        validateDates(request.batchType(), request.startDate(), request.endDate());

        Batch saved = batchRepository.save(Batch.builder()
                .courseId(courseIds.get(0))
                .courseIds(new java.util.LinkedHashSet<>(courseIds))
                .name(request.name())
                .description(request.description())
                .batchType(request.batchType())
                .trainerMembershipId(trainerIds.isEmpty() ? null : trainerIds.get(0))
                .startDate(request.startDate())
                .endDate(request.batchType() == BatchType.TEMPORARY ? request.endDate() : null)
                .meetingLink(cleanLink(request.meetingLink()))
                .build());

        replaceTrainers(saved.getId(), trainerIds);
        // Enrolling here rather than making the client follow up with N addMember calls: a
        // half-enrolled batch after a dropped request is worse than an atomic failure.
        for (UUID studentId : nullSafe(request.studentMembershipIds())) {
            addMember(saved.getId(), studentId);
        }
        return buildResponse(saved);
    }

    /** A pasted link is trimmed; a blank one means "no link". */
    private static String cleanLink(String link) {
        return link == null || link.isBlank() ? null : link.trim();
    }

    /**
     * Editing an existing batch. The roster is replaced wholesale rather than diffed by the
     * client, so removing a student is just "send the list without them".
     */
    @Transactional
    @Auditable(action = "BATCH_UPDATED", entityType = "batch")
    public BatchResponse update(UUID batchId, UpdateBatchRequest request) {
        Batch batch = findOrThrow(batchId);
        // Working inside a multi-course batch needs the permission on at least one of its courses;
        // anything that changes WHICH courses it spans is checked course by course below.
        courseFeatureGuard.assertAnyOfCourses(batch.allCourseIds(), FeatureKey.BATCH_CREATION);

        List<UUID> trainerIds = resolveTrainerIds(request.trainerMembershipIds(), null);
        validateDates(batch.getBatchType(), request.startDate(), request.endDate());

        batch.setName(request.name());
        batch.setDescription(request.description());
        batch.setTrainerMembershipId(trainerIds.isEmpty() ? null : trainerIds.get(0));
        batch.setStartDate(request.startDate());
        batch.setEndDate(batch.getBatchType() == BatchType.TEMPORARY ? request.endDate() : null);
        batch.setMeetingLink(cleanLink(request.meetingLink()));

        Set<UUID> removedCourses = applyCourseChange(batch, request.courseIds());
        batchRepository.save(batch);

        replaceTrainers(batchId, trainerIds);
        syncRoster(batch, nullSafe(request.studentMembershipIds()));
        assertNoStudentLeftWithoutACourse(batch, removedCourses);
        return buildResponse(batch);
    }

    /**
     * Applies the requested set of courses to the batch and returns the ones that were dropped. A null
     * request leaves the courses alone (a client that predates multi-course batches). The old primary stays
     * primary while it is still covered, so adding Advanced never reshuffles which course the batch
     * "belongs" to. Adding or dropping a course needs Batch creation on THAT course.
     */
    private Set<UUID> applyCourseChange(Batch batch, List<UUID> requested) {
        if (requested == null) {
            return Set.of();
        }
        List<UUID> wanted = resolveCourseIds(requested, null);
        Set<UUID> current = batch.allCourseIds();
        Set<UUID> added = new java.util.LinkedHashSet<>(wanted);
        added.removeAll(current);
        Set<UUID> removed = new java.util.LinkedHashSet<>(current);
        removed.removeAll(wanted);
        if (added.isEmpty() && removed.isEmpty()) {
            return Set.of();
        }

        assertCoursesInActiveAcademy(List.copyOf(added));
        for (UUID courseId : added) {
            courseFeatureGuard.assertCourseFeature(courseId, FeatureKey.BATCH_CREATION);
        }
        for (UUID courseId : removed) {
            courseFeatureGuard.assertCourseFeature(courseId, FeatureKey.BATCH_CREATION);
        }

        List<UUID> ordered = new java.util.ArrayList<>(wanted);
        if (wanted.contains(batch.getCourseId())) {
            ordered.remove(batch.getCourseId());
            ordered.add(0, batch.getCourseId());
        }
        batch.setCourses(ordered);
        return removed;
    }

    /**
     * Dropping a course from a batch must not strand its students in a class that no longer teaches their
     * course. Checked AFTER the roster was synced, so removing the students in the same save is fine.
     */
    private void assertNoStudentLeftWithoutACourse(Batch batch, Set<UUID> removedCourses) {
        if (removedCourses.isEmpty()) {
            return;
        }
        Set<UUID> remaining = batch.allCourseIds();
        List<UUID> memberIds = batchMemberRepository.findByBatchId(batch.getId()).stream()
                .map(BatchMember::getMembershipId).toList();
        Map<UUID, Set<UUID>> enrolled = activeEnrolments(memberIds);
        for (UUID memberId : memberIds) {
            Set<UUID> theirs = enrolled.getOrDefault(memberId, Set.of());
            boolean hadARemovedCourse = theirs.stream().anyMatch(removedCourses::contains);
            boolean stillHasOne = theirs.stream().anyMatch(remaining::contains);
            if (hadARemovedCourse && !stillHasOne) {
                throw new ConflictException("Some students of a course you removed are still in this batch - "
                        + "move them out of the batch first, or keep the course.");
            }
        }
    }

    /** Deactivating is the reversible alternative to {@link #delete}: history stays intact, the
     * batch just drops off attendance and fee-collection lists. */
    @Transactional
    @Auditable(action = "BATCH_STATUS_CHANGED", entityType = "batch")
    public BatchResponse setStatus(UUID batchId, BatchStatus status) {
        Batch batch = findOrThrow(batchId);
        courseFeatureGuard.assertAllCourses(batch.allCourseIds(), FeatureKey.BATCH_CREATION);
        batch.setStatus(status);
        return buildResponse(batchRepository.save(batch));
    }

    @Transactional(readOnly = true)
    public BatchResponse get(UUID batchId) {
        return buildResponse(findOrThrow(batchId));
    }

    @Transactional(readOnly = true)
    public List<BatchResponse> listForCourse(UUID courseId) {
        // A trainer given only some of this course's batches is offered only those. (No permission check
        // here: students and every kind of staff list a course's batches for their pickers.)
        var scope = courseFeatureGuard.batchScope(courseId);
        return buildResponses(batchRepository.findByCourseId(courseId).stream()
                .filter(b -> CourseFeatureGuard.inScope(scope, b.getId()))
                .toList());
    }

    /** Every batch in the active academy, across all its courses - the batch list screen's source,
     * which is organised by batch rather than drilled into per course. Joined through courses
     * because Batch has no academy_id of its own. */
    @Transactional(readOnly = true)
    public List<BatchResponse> listForActiveAcademy() {
        // Scoped to the caller's own courses. A Trainer granted Batch Creation on Guitar has no
        // business seeing - let alone editing - the Bharatanatyam batches listed beside it.
        // Batch creation OR student registration: the registration form offers batches to place a new
        // student in, so someone who registers students but does not build batches still needs them.
        var visible = courseFeatureGuard.visibleCourseIdsAny(FeatureKey.BATCH_CREATION, FeatureKey.STUDENT_REGISTRATION);

        Set<UUID> courseIds = courseRepository.findByAcademyIdOrderByNameAsc(TenantContext.currentAcademyId())
                .stream().map(Course::getId)
                .filter(id -> visible.isEmpty() || visible.get().contains(id))
                .collect(Collectors.toSet());
        if (courseIds.isEmpty()) {
            return List.of();
        }
        Map<UUID, java.util.Optional<Set<UUID>>> scopeByCourse = new java.util.HashMap<>();
        // A multi-course batch is listed once, when the caller has it through ANY course they can see
        // and it is within the batches they were given for that course.
        return buildResponses(batchRepository.findByCourseIdIn(courseIds).stream()
                .filter(b -> b.allCourseIds().stream()
                        .filter(courseIds::contains)
                        .anyMatch(c -> CourseFeatureGuard.inScope(
                                scopeByCourse.computeIfAbsent(c, courseFeatureGuard::batchScope), b.getId())))
                .toList());
    }

    /** Just the batch(es) ONE membership actually belongs to, across every course - e.g. a
     * Student's own "my batches" view, which must show only what they're mapped into (usually
     * one Regular batch per course they're enrolled in), never every batch the course happens to
     * have. Scoped to the active academy so a Trainer/Admin can't probe another academy's
     * membership IDs through this endpoint (same guard as CourseService.listForMembership). */
    @Transactional(readOnly = true)
    public List<BatchResponse> listForMembership(UUID membershipId) {
        AcademyMembership membership = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Membership not found: " + membershipId));
        if (!membership.getAcademyId().equals(TenantContext.currentAcademyId())) {
            throw new ForbiddenException("That membership does not belong to the active academy");
        }

        Set<UUID> batchIds = batchMemberRepository.findByMembershipId(membershipId).stream()
                .map(BatchMember::getBatchId).collect(Collectors.toSet());
        return buildResponses(batchRepository.findAllById(batchIds));
    }

    /**
     * PRD 3.6: "A student can belong to only one Regular batch per course at a time... but can
     * additionally be added to any number of Temporary batches." Temporary batches (e.g. an
     * annual-day rehearsal) intentionally skip this check - they exist specifically to pull
     * students across multiple Regular batches (PRD 3.7.3).
     */
    @Transactional
    @Auditable(action = "BATCH_MEMBER_ADDED", entityType = "batch_member")
    public void addMember(UUID batchId, UUID membershipId) {
        Batch batch = batchRepository.findById(batchId)
                .orElseThrow(() -> new ResourceNotFoundException("Batch not found: " + batchId));
        // Per-course enforcement: the controller's @RequiresFeature only checks the union across
        // all courses - without this, a Trainer granted BATCH_CREATION on Guitar could enrol
        // students into a Bharatanatyam batch.
        // Placing a student in a batch is part of registering them, so Student registration is enough
        // on this course too - not only Batch creation. In a batch spanning several courses the caller
        // needs it on the student's OWN course: a Basic trainer cannot place an Advanced student.
        courseFeatureGuard.assertAnyOfCourses(coursesOfStudentInBatch(batch, membershipId),
                FeatureKey.BATCH_CREATION, FeatureKey.STUDENT_REGISTRATION);

        if (batch.getBatchType() == BatchType.REGULAR && isAlreadyInAnotherRegularBatchForCourse(membershipId, batch)) {
            throw new ConflictException(
                    "This student is already in a Regular batch for this course - move them out of the existing " +
                    "batch first, or use a Temporary batch instead.");
        }

        if (batchMemberRepository.existsByBatchIdAndMembershipId(batchId, membershipId)) {
            return; // idempotent - already a member
        }
        batchMemberRepository.save(BatchMember.builder().batchId(batchId).membershipId(membershipId).build());
    }

    @Transactional(readOnly = true)
    public List<UUID> listMemberIds(UUID batchId) {
        return rosterFor(findOrThrow(batchId)).students().stream()
                .map(BatchMemberSummaryResponse::membershipId).collect(Collectors.toList());
    }

    /** Attendance marking's roster source - a real name and photo per student instead of a bare
     * membership UUID (mirrors StudentRegistrationService.listStudentsForCourse's shape). */
    @Transactional(readOnly = true)
    public List<BatchMemberSummaryResponse> listMemberSummaries(UUID batchId) {
        return rosterFor(findOrThrow(batchId)).students();
    }

    /** The same roster plus how many students the caller is NOT shown (see {@link #rosterFor}). */
    @Transactional(readOnly = true)
    public BatchRosterResponse getRoster(UUID batchId) {
        return rosterFor(findOrThrow(batchId));
    }

    /**
     * The batch's students as the CALLER may see them. A batch can span Basic, Intermediate and Advanced;
     * a trainer mapped to two of those sees the students of those two and only a count of the rest. A
     * student in the batch, an admin, and a trainer who teaches the batch but holds none of its courses
     * (the old behaviour) still see everyone.
     */
    private BatchRosterResponse rosterFor(Batch batch) {
        Set<UUID> visibleCourses = visibleCoursesForRoster(batch);
        List<UUID> membershipIds = batchMemberRepository.findByBatchId(batch.getId()).stream()
                .map(BatchMember::getMembershipId).toList();
        if (membershipIds.isEmpty()) {
            return new BatchRosterResponse(List.of(), 0);
        }

        Map<UUID, Set<UUID>> enrolled = activeEnrolments(membershipIds);
        Set<UUID> inBatch = batch.allCourseIds();
        Map<UUID, String> courseNames = courseRepository.findAllById(inBatch).stream()
                .collect(Collectors.toMap(Course::getId, Course::getName, (a, b) -> a));

        List<AcademyMembership> memberships = membershipRepository.findAllById(membershipIds);
        Map<UUID, User> usersById = userRepository.findAllById(
                memberships.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        List<BatchMemberSummaryResponse> shown = new java.util.ArrayList<>();
        for (AcademyMembership m : memberships) {
            Set<UUID> theirs = studentCourses.inBatch(batch, m.getId(), enrolled);
            // Batch order, so a student in two of the batch's courses is tagged with the first.
            UUID tag = null;
            for (UUID courseId : inBatch) {
                if (theirs.contains(courseId) && (visibleCourses == null || visibleCourses.contains(courseId))) {
                    tag = courseId;
                    break;
                }
            }
            if (tag == null) {
                continue; // none of their courses is one the caller holds
            }
            User u = usersById.get(m.getUserId());
            shown.add(new BatchMemberSummaryResponse(m.getId(), u.getId(), u.getUsername(), u.getFullName(),
                    u.getProfileImageUrl(), tag, courseNames.get(tag)));
        }
        return new BatchRosterResponse(shown, memberships.size() - shown.size());
    }

    /** Unmapping is idempotent, same as addMember being idempotent - removing someone who was
     * never (or no longer) a member just leaves the roster as-is rather than erroring. */
    @Transactional
    @Auditable(action = "BATCH_MEMBER_REMOVED", entityType = "batch_member")
    public void removeMember(UUID batchId, UUID membershipId) {
        Batch batch = findOrThrow(batchId);
        // The student's own course, not just any of the batch's: a Basic trainer cannot remove an Advanced student.
        courseFeatureGuard.assertAnyOfCourses(coursesOfStudentInBatch(batch, membershipId), FeatureKey.BATCH_CREATION);
        batchMemberRepository.deleteByBatchIdAndMembershipId(batchId, membershipId);
    }

    /** Genuine hard delete - unlike a Course, a batch that never held a class carries no history
     * worth preserving. The roster goes with it: students are only linked to the batch, so there is
     * nothing of theirs to lose, and making someone unmap each student first (and then fail to save)
     * only got in the way. One guard remains, so real history is never silently lost:
     * <ul>
     *   <li>any batch that has actually HELD a class (i.e. has real attendance history) can't be
     *       deleted at all - deactivate it instead, the same as a Course.</li>
     * </ul>
     */
    @Transactional
    @Auditable(action = "BATCH_DELETED", entityType = "batch")
    public void delete(UUID batchId) {
        Batch batch = batchRepository.findById(batchId)
                .orElseThrow(() -> new ResourceNotFoundException("Batch not found: " + batchId));
        courseFeatureGuard.assertAllCourses(batch.allCourseIds(), FeatureKey.BATCH_CREATION);

        boolean hasAttendanceHistory = classInstanceRepository.findByBatchId(batchId).stream()
                .anyMatch(ci -> ci.getStatus() == ClassInstanceStatus.HELD);
        if (hasAttendanceHistory) {
            throw new ConflictException("This batch has attendance history and can't be deleted - deactivate it instead.");
        }

        scheduleRepository.deleteByBatchId(batchId);
        classInstanceRepository.deleteByBatchId(batchId);
        batchTrainerRepository.deleteByBatchId(batchId);
        batchMemberRepository.deleteByBatchId(batchId);
        // Material aimed at this batch stops going to it; a file whose ONLY audience was this batch goes too -
        // leaving it would orphan a row nothing can ever reach or clean up.
        studyMaterialService.detachBatch(batchId);
        batchRepository.delete(batch);
    }

    /**
     * Who may read a batch's roster (names and photos of its students): someone IN the batch, its own
     * trainer, or staff who hold any permission on this course and have this batch within the batches
     * they were given. Previously any signed-in trainer could list any batch's students, including those
     * of courses they have nothing to do with.
     */
    private Set<UUID> visibleCoursesForRoster(Batch batch) {
        UUID me = TenantContext.currentMembershipId();
        if (batchMemberRepository.existsByBatchIdAndMembershipId(batch.getId(), me)) {
            return null; // a classmate sees the class
        }
        String[] anyFeature = FeatureKey.ALL_DELEGABLE.toArray(String[]::new);
        var visible = courseFeatureGuard.visibleCourseIdsAny(anyFeature);
        if (visible.isEmpty()) {
            return null; // an admin: no restriction
        }
        Set<UUID> mine = batch.allCourseIds().stream()
                .filter(visible.get()::contains)
                .collect(Collectors.toCollection(java.util.LinkedHashSet::new));
        boolean teachesIt = batchTrainerRepository.findByBatchId(batch.getId()).stream()
                .anyMatch(t -> me.equals(t.getTrainerMembershipId()));
        if (teachesIt) {
            // The batch's own trainer. If they hold some of its courses they see those students; if they
            // hold none of them (they were put on the batch directly) they keep seeing the whole class.
            return mine.isEmpty() ? null : mine;
        }
        courseFeatureGuard.assertBatchAccess(batch.allCourseIds(), batch.getId(), anyFeature);
        return mine;
    }

    private Batch findOrThrow(UUID batchId) {
        return batchRepository.findById(batchId)
                .orElseThrow(() -> new ResourceNotFoundException("Batch not found: " + batchId));
    }

    private static <T> List<T> nullSafe(List<T> list) {
        return list == null ? List.of() : list;
    }

    /**
     * Reconciles the two ways a client can name trainers. The plural field wins when present;
     * the singular is the older shape and is only consulted as a fallback.
     *
     * <p>De-duplicated while preserving order, because the first entry becomes the primary
     * trainer and a duplicate would otherwise be able to displace it.
     */
    private List<UUID> resolveTrainerIds(List<UUID> plural, UUID singular) {
        List<UUID> source = plural != null && !plural.isEmpty()
                ? plural
                : (singular == null ? List.of() : List.of(singular));
        return source.stream().filter(Objects::nonNull).distinct().collect(Collectors.toList());
    }

    /**
     * A TEMPORARY batch is defined by running between two dates - one without an end date is
     * indistinguishable from a Regular batch and would never stop generating classes. A Regular
     * batch conversely has no end date, so passing one is a client bug worth surfacing rather
     * than quietly discarding.
     */
    private void validateDates(BatchType type, LocalDate startDate, LocalDate endDate) {
        if (type == BatchType.TEMPORARY) {
            if (startDate == null || endDate == null) {
                throw new BadRequestException("A temporary batch needs both a start and an end date.");
            }
            if (endDate.isBefore(startDate)) {
                throw new BadRequestException("The end date must be on or after the start date.");
            }
        } else if (endDate != null) {
            throw new BadRequestException(
                    "A regular batch runs until it is deactivated and cannot have an end date.");
        }
    }

    /** Replaces the batch's trainer set outright - simpler and less error-prone than diffing, and
     * the set is at most a handful of rows. */
    private void replaceTrainers(UUID batchId, List<UUID> trainerIds) {
        batchTrainerRepository.deleteByBatchId(batchId);
        for (UUID trainerId : trainerIds) {
            batchTrainerRepository.save(BatchTrainer.builder()
                    .batchId(batchId).trainerMembershipId(trainerId).build());
        }
    }

    /**
     * Makes the roster match {@code desired} exactly.
     *
     * <p>Removals happen before additions on purpose: moving a student between two Regular batches
     * of the same course in one save would otherwise trip the one-batch-per-course rule against
     * the membership we are in the middle of removing them from.
     */
    private void syncRoster(Batch batch, List<UUID> desired) {
        UUID batchId = batch.getId();
        Set<UUID> target = new java.util.LinkedHashSet<>(desired);
        Set<UUID> current = batchMemberRepository.findByBatchId(batchId).stream()
                .map(BatchMember::getMembershipId).collect(Collectors.toSet());
        // The editor only ever received the students the caller may see, so a student missing from the
        // list is "not shown to them", not "taken out". Only those whose course the caller can manage
        // are actually removed; the rest stay exactly as they were.
        Map<UUID, Set<UUID>> enrolled = activeEnrolments(current);

        for (UUID existing : current) {
            if (!target.contains(existing)) {
                if (callerManages(batch, existing, enrolled)) {
                    batchMemberRepository.deleteByBatchIdAndMembershipId(batchId, existing);
                }
            }
        }
        for (UUID wanted : target) {
            if (!current.contains(wanted)) {
                addMember(batchId, wanted);
            }
        }
    }

    /**
     * One Regular batch per COURSE per student. With batches that span several courses the course that
     * counts is the student's own: a Basic student in a Basic + Intermediate + Advanced batch holds Basic
     * there, so a second Regular batch that also covers Basic is refused, while one covering only
     * Intermediate and Advanced is not - they are not enrolled in those.
     */
    private boolean isAlreadyInAnotherRegularBatchForCourse(UUID membershipId, Batch targetBatch) {
        List<BatchMember> existingMemberships = batchMemberRepository.findByMembershipId(membershipId);
        if (existingMemberships.isEmpty()) {
            return false;
        }
        Set<UUID> existingBatchIds = existingMemberships.stream().map(BatchMember::getBatchId).collect(Collectors.toSet());
        Set<UUID> inTarget = coursesOfStudentInBatch(targetBatch, membershipId);
        return batchRepository.findAllById(existingBatchIds).stream()
                .filter(b -> b.getBatchType() == BatchType.REGULAR && !b.getId().equals(targetBatch.getId()))
                .anyMatch(b -> coursesOfStudentInBatch(b, membershipId).stream().anyMatch(inTarget::contains));
    }

    /**
     * The courses a student holds WITHIN a batch: the batch's courses they are actively enrolled in. A
     * student with no enrolment in any of them (a legacy roster, or a data slip) is treated as belonging
     * to all of the batch's courses, so the rules fail safe rather than letting them through unchecked.
     */
    private Set<UUID> coursesOfStudentInBatch(Batch batch, UUID membershipId) {
        return studentCourses.inBatch(batch, membershipId);
    }

    private Map<UUID, Set<UUID>> activeEnrolments(java.util.Collection<UUID> membershipIds) {
        return studentCourses.activeEnrolments(membershipIds);
    }

    /** Distinct, non-null course ids in the order given (the first is the primary). */
    private List<UUID> resolveCourseIds(List<UUID> plural, UUID singular) {
        List<UUID> source = plural != null && !plural.isEmpty()
                ? plural
                : (singular == null ? List.of() : List.of(singular));
        List<UUID> ids = source.stream().filter(Objects::nonNull).distinct().collect(Collectors.toList());
        if (ids.isEmpty()) {
            throw new BadRequestException("Pick at least one course for the batch.");
        }
        return ids;
    }

    /** Every course must exist in the caller's academy - a course id from another academy is "not found". */
    private void assertCoursesInActiveAcademy(List<UUID> courseIds) {
        if (courseIds.isEmpty()) {
            return;
        }
        UUID academyId = TenantContext.currentAcademyId();
        Map<UUID, Course> found = courseRepository.findAllById(courseIds).stream()
                .collect(Collectors.toMap(Course::getId, c -> c));
        for (UUID id : courseIds) {
            Course course = found.get(id);
            if (course == null || !academyId.equals(course.getAcademyId())) {
                throw new ResourceNotFoundException("Course not found: " + id);
            }
        }
    }

    /** Whether the caller holds Batch creation on at least one of this student's courses in the batch. */
    private boolean callerManages(Batch batch, UUID membershipId, Map<UUID, Set<UUID>> enrolled) {
        return !courseFeatureGuard.heldCourses(studentCourses.inBatch(batch, membershipId, enrolled),
                FeatureKey.BATCH_CREATION).isEmpty();
    }

    /** Resolves a set of trainer memberships to display names in a single pair of findAllById
     * calls, rather than one lookup per batch. */
    private Map<UUID, String> trainerNamesFor(Set<UUID> membershipIds) {
        Set<UUID> trainerMembershipIds = membershipIds.stream()
                .filter(Objects::nonNull).collect(Collectors.toSet());
        if (trainerMembershipIds.isEmpty()) {
            return Map.of();
        }
        List<AcademyMembership> trainerMemberships = membershipRepository.findAllById(trainerMembershipIds);
        Map<UUID, User> usersById = userRepository.findAllById(
                trainerMemberships.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        Map<UUID, String> result = new HashMap<>();
        for (AcademyMembership m : trainerMemberships) {
            User u = usersById.get(m.getUserId());
            if (u != null) {
                result.put(m.getId(), u.getFullName());
            }
        }
        return result;
    }

    private BatchResponse buildResponse(Batch batch) {
        return buildResponses(List.of(batch)).get(0);
    }

    /**
     * Builds responses for a whole list with a fixed number of queries regardless of list length -
     * one for the trainer links, one for the memberships, one for the users, one for the rosters.
     * Doing this per batch is the N+1 that makes a 40-batch academy's list screen crawl.
     */
    private List<BatchResponse> buildResponses(List<Batch> batches) {
        if (batches.isEmpty()) {
            return List.of();
        }
        List<UUID> batchIds = batches.stream().map(Batch::getId).toList();

        Map<UUID, List<UUID>> trainerIdsByBatch = new HashMap<>();
        for (BatchTrainer link : batchTrainerRepository.findByBatchIdIn(batchIds)) {
            trainerIdsByBatch.computeIfAbsent(link.getBatchId(), k -> new java.util.ArrayList<>())
                    .add(link.getTrainerMembershipId());
        }

        Map<UUID, String> namesByMembership = trainerNamesFor(
                trainerIdsByBatch.values().stream().flatMap(List::stream).collect(Collectors.toSet()));

        Map<UUID, Integer> rosterSizes = new HashMap<>();
        for (BatchMember member : batchMemberRepository.findByBatchIdIn(batchIds)) {
            rosterSizes.merge(member.getBatchId(), 1, Integer::sum);
        }

        Map<UUID, List<com.nest.app.scheduling.entity.Schedule>> slotsByBatch = new HashMap<>();
        for (com.nest.app.scheduling.entity.Schedule slot :
                scheduleRepository.findByBatchIdInAndEffectiveToIsNull(batchIds)) {
            slotsByBatch.computeIfAbsent(slot.getBatchId(), k -> new java.util.ArrayList<>()).add(slot);
        }

        Set<UUID> everyCourseId = batches.stream().flatMap(b -> b.allCourseIds().stream())
                .collect(Collectors.toCollection(java.util.LinkedHashSet::new));
        Map<UUID, String> courseNames = courseRepository.findAllById(everyCourseId).stream()
                .collect(Collectors.toMap(Course::getId, Course::getName, (a, c) -> a));

        List<BatchResponse> result = new java.util.ArrayList<>();
        for (Batch b : batches) {
            List<com.nest.app.scheduling.entity.Schedule> slots = slotsByBatch.getOrDefault(b.getId(), List.of());
            List<BatchResponse.TrainerSummary> trainers = trainerIdsByBatch
                    .getOrDefault(b.getId(), List.of()).stream()
                    .map(id -> new BatchResponse.TrainerSummary(id, namesByMembership.get(id)))
                    // A membership that no longer resolves to a user (deleted account) is dropped
                    // rather than rendered as a blank chip in the trainer list.
                    .filter(t -> t.name() != null)
                    .sorted(java.util.Comparator.comparing(BatchResponse.TrainerSummary::name))
                    .collect(Collectors.toList());

            result.add(new BatchResponse(
                    b.getId(), b.getCourseId(), b.getName(), b.getDescription(), b.getBatchType(),
                    // A batch with no trainer yet has no primary trainer to name. The lookup map can be an
                    // immutable empty Map.of(), whose get(null) throws instead of returning null - which
                    // made creating or listing a trainerless batch a 500.
                    b.getTrainerMembershipId(),
                    b.getTrainerMembershipId() == null ? null : namesByMembership.get(b.getTrainerMembershipId()),
                    b.getStatus(), b.getStartDate(), b.getEndDate(), trainers,
                    rosterSizes.getOrDefault(b.getId(), 0),
                    slots.isEmpty() ? null : slots.get(0).getStartTime().toString(),
                    slots.isEmpty() ? null : slots.get(0).getEndTime().toString(),
                    slots.stream().map(com.nest.app.scheduling.entity.Schedule::getDayOfWeek).distinct().sorted().toList(),
                    b.getMeetingLink(),
                    b.allCourseIds().stream()
                            .map(id -> new BatchResponse.CourseSummary(id, courseNames.getOrDefault(id, "Course")))
                            .toList()));
        }
        return result;
    }
}
