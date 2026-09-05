package com.nest.app.enrolment.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.curriculum.repository.StudyMaterialRepository;
import com.nest.app.enrolment.dto.BatchMemberSummaryResponse;
import com.nest.app.enrolment.dto.BatchResponse;
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
    private final StudyMaterialRepository studyMaterialRepository;
    private final CourseFeatureGuard courseFeatureGuard;

    public BatchService(BatchRepository batchRepository, BatchMemberRepository batchMemberRepository,
                         BatchTrainerRepository batchTrainerRepository,
                         AcademyMembershipRepository membershipRepository, UserRepository userRepository,
                         CourseRepository courseRepository,
                         ScheduleRepository scheduleRepository, ClassInstanceRepository classInstanceRepository,
                         StudyMaterialRepository studyMaterialRepository,
                         CourseFeatureGuard courseFeatureGuard) {
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.batchTrainerRepository = batchTrainerRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.courseRepository = courseRepository;
        this.scheduleRepository = scheduleRepository;
        this.classInstanceRepository = classInstanceRepository;
        this.studyMaterialRepository = studyMaterialRepository;
        this.courseFeatureGuard = courseFeatureGuard;
    }

    @Transactional
    @Auditable(action = "BATCH_CREATED", entityType = "batch")
    public BatchResponse create(CreateBatchRequest request) {
        // Per-course enforcement: a Trainer must hold BATCH_CREATION on THIS course (Admins bypass).
        courseFeatureGuard.assertCourseFeature(request.courseId(), FeatureKey.BATCH_CREATION);

        List<UUID> trainerIds = resolveTrainerIds(request.trainerMembershipIds(), request.trainerMembershipId());
        validateDates(request.batchType(), request.startDate(), request.endDate());

        Batch saved = batchRepository.save(Batch.builder()
                .courseId(request.courseId())
                .name(request.name())
                .description(request.description())
                .batchType(request.batchType())
                .trainerMembershipId(trainerIds.isEmpty() ? null : trainerIds.get(0))
                .startDate(request.startDate())
                .endDate(request.batchType() == BatchType.TEMPORARY ? request.endDate() : null)
                .build());

        replaceTrainers(saved.getId(), trainerIds);
        // Enrolling here rather than making the client follow up with N addMember calls: a
        // half-enrolled batch after a dropped request is worse than an atomic failure.
        for (UUID studentId : nullSafe(request.studentMembershipIds())) {
            addMember(saved.getId(), studentId);
        }
        return buildResponse(saved);
    }

    /**
     * Editing an existing batch. The roster is replaced wholesale rather than diffed by the
     * client, so removing a student is just "send the list without them".
     */
    @Transactional
    @Auditable(action = "BATCH_UPDATED", entityType = "batch")
    public BatchResponse update(UUID batchId, UpdateBatchRequest request) {
        Batch batch = findOrThrow(batchId);
        courseFeatureGuard.assertCourseFeature(batch.getCourseId(), FeatureKey.BATCH_CREATION);

        List<UUID> trainerIds = resolveTrainerIds(request.trainerMembershipIds(), null);
        validateDates(batch.getBatchType(), request.startDate(), request.endDate());

        batch.setName(request.name());
        batch.setDescription(request.description());
        batch.setTrainerMembershipId(trainerIds.isEmpty() ? null : trainerIds.get(0));
        batch.setStartDate(request.startDate());
        batch.setEndDate(batch.getBatchType() == BatchType.TEMPORARY ? request.endDate() : null);
        batchRepository.save(batch);

        replaceTrainers(batchId, trainerIds);
        syncRoster(batchId, nullSafe(request.studentMembershipIds()));
        return buildResponse(batch);
    }

    /** Deactivating is the reversible alternative to {@link #delete}: history stays intact, the
     * batch just drops off attendance and fee-collection lists. */
    @Transactional
    @Auditable(action = "BATCH_STATUS_CHANGED", entityType = "batch")
    public BatchResponse setStatus(UUID batchId, BatchStatus status) {
        Batch batch = findOrThrow(batchId);
        courseFeatureGuard.assertCourseFeature(batch.getCourseId(), FeatureKey.BATCH_CREATION);
        batch.setStatus(status);
        return buildResponse(batchRepository.save(batch));
    }

    @Transactional(readOnly = true)
    public BatchResponse get(UUID batchId) {
        return buildResponse(findOrThrow(batchId));
    }

    @Transactional(readOnly = true)
    public List<BatchResponse> listForCourse(UUID courseId) {
        return buildResponses(batchRepository.findByCourseId(courseId));
    }

    /** Every batch in the active academy, across all its courses - the batch list screen's source,
     * which is organised by batch rather than drilled into per course. Joined through courses
     * because Batch has no academy_id of its own. */
    @Transactional(readOnly = true)
    public List<BatchResponse> listForActiveAcademy() {
        // Scoped to the caller's own courses. A Trainer granted Batch Creation on Guitar has no
        // business seeing - let alone editing - the Bharatanatyam batches listed beside it.
        var visible = courseFeatureGuard.visibleCourseIds(FeatureKey.BATCH_CREATION);

        Set<UUID> courseIds = courseRepository.findByAcademyIdOrderByNameAsc(TenantContext.currentAcademyId())
                .stream().map(Course::getId)
                .filter(id -> visible.isEmpty() || visible.get().contains(id))
                .collect(Collectors.toSet());
        if (courseIds.isEmpty()) {
            return List.of();
        }
        return buildResponses(batchRepository.findByCourseIdIn(courseIds));
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
        return batchMemberRepository.findByBatchId(batchId).stream().map(BatchMember::getMembershipId).collect(Collectors.toList());
    }

    /** Attendance marking's roster source - a real name and photo per student instead of a bare
     * membership UUID (mirrors StudentRegistrationService.listStudentsForCourse's shape). */
    @Transactional(readOnly = true)
    public List<BatchMemberSummaryResponse> listMemberSummaries(UUID batchId) {
        List<UUID> membershipIds = batchMemberRepository.findByBatchId(batchId).stream()
                .map(BatchMember::getMembershipId).toList();
        if (membershipIds.isEmpty()) {
            return List.of();
        }

        List<AcademyMembership> memberships = membershipRepository.findAllById(membershipIds);
        Map<UUID, User> usersById = userRepository.findAllById(
                memberships.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        return memberships.stream()
                .map(m -> {
                    User u = usersById.get(m.getUserId());
                    return new BatchMemberSummaryResponse(m.getId(), u.getId(), u.getUsername(), u.getFullName(), u.getProfileImageUrl());
                })
                .collect(Collectors.toList());
    }

    /** Unmapping is idempotent, same as addMember being idempotent - removing someone who was
     * never (or no longer) a member just leaves the roster as-is rather than erroring. */
    @Transactional
    @Auditable(action = "BATCH_MEMBER_REMOVED", entityType = "batch_member")
    public void removeMember(UUID batchId, UUID membershipId) {
        batchMemberRepository.deleteByBatchIdAndMembershipId(batchId, membershipId);
    }

    /** Genuine hard delete - unlike a Course, an empty batch that never held a class carries no
     * history worth preserving. Two guards make sure nothing is ever silently lost:
     * <ul>
     *   <li>any current roster must be unmapped first (explicit, so a delete can never look like
     *       "where did my batch go" to a student who was still in it);</li>
     *   <li>any batch that has actually HELD a class (i.e. has real attendance history) can't be
     *       deleted at all - deactivate it instead, the same as a Course.</li>
     * </ul>
     */
    @Transactional
    @Auditable(action = "BATCH_DELETED", entityType = "batch")
    public void delete(UUID batchId) {
        Batch batch = batchRepository.findById(batchId)
                .orElseThrow(() -> new ResourceNotFoundException("Batch not found: " + batchId));

        if (!batchMemberRepository.findByBatchId(batchId).isEmpty()) {
            throw new ConflictException("Please de-link the students from this batch first.");
        }

        boolean hasAttendanceHistory = classInstanceRepository.findByBatchId(batchId).stream()
                .anyMatch(ci -> ci.getStatus() == ClassInstanceStatus.HELD);
        if (hasAttendanceHistory) {
            throw new ConflictException("This batch has attendance history and can't be deleted - deactivate it instead.");
        }

        scheduleRepository.deleteByBatchId(batchId);
        classInstanceRepository.deleteByBatchId(batchId);
        batchTrainerRepository.deleteByBatchId(batchId);
        // Material shared with a batch has no meaning without it - leaving these behind would
        // orphan rows nothing can ever reach or clean up.
        studyMaterialRepository.deleteByBatchId(batchId);
        batchRepository.delete(batch);
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
    private void syncRoster(UUID batchId, List<UUID> desired) {
        Set<UUID> target = new java.util.LinkedHashSet<>(desired);
        Set<UUID> current = batchMemberRepository.findByBatchId(batchId).stream()
                .map(BatchMember::getMembershipId).collect(Collectors.toSet());

        for (UUID existing : current) {
            if (!target.contains(existing)) {
                batchMemberRepository.deleteByBatchIdAndMembershipId(batchId, existing);
            }
        }
        for (UUID wanted : target) {
            if (!current.contains(wanted)) {
                addMember(batchId, wanted);
            }
        }
    }

    private boolean isAlreadyInAnotherRegularBatchForCourse(UUID membershipId, Batch targetBatch) {
        List<BatchMember> existingMemberships = batchMemberRepository.findByMembershipId(membershipId);
        if (existingMemberships.isEmpty()) {
            return false;
        }
        Set<UUID> existingBatchIds = existingMemberships.stream().map(BatchMember::getBatchId).collect(Collectors.toSet());
        return batchRepository.findAllById(existingBatchIds).stream()
                .anyMatch(b -> b.getBatchType() == BatchType.REGULAR
                        && b.getCourseId().equals(targetBatch.getCourseId())
                        && !b.getId().equals(targetBatch.getId()));
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

        List<BatchResponse> result = new java.util.ArrayList<>();
        for (Batch b : batches) {
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
                    b.getTrainerMembershipId(), namesByMembership.get(b.getTrainerMembershipId()),
                    b.getStatus(), b.getStartDate(), b.getEndDate(), trainers,
                    rosterSizes.getOrDefault(b.getId(), 0)));
        }
        return result;
    }
}
