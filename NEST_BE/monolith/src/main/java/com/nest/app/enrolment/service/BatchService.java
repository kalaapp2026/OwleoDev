package com.nest.app.enrolment.service;

import com.nest.app.enrolment.dto.BatchMemberSummaryResponse;
import com.nest.app.enrolment.dto.BatchResponse;
import com.nest.app.enrolment.dto.CreateBatchRequest;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchType;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.app.scheduling.repository.ScheduleRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

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
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;
    private final ScheduleRepository scheduleRepository;
    private final ClassInstanceRepository classInstanceRepository;

    public BatchService(BatchRepository batchRepository, BatchMemberRepository batchMemberRepository,
                         AcademyMembershipRepository membershipRepository, UserRepository userRepository,
                         ScheduleRepository scheduleRepository, ClassInstanceRepository classInstanceRepository) {
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.scheduleRepository = scheduleRepository;
        this.classInstanceRepository = classInstanceRepository;
    }

    @Transactional
    @Auditable(action = "BATCH_CREATED", entityType = "batch")
    public BatchResponse create(CreateBatchRequest request) {
        Batch batch = Batch.builder()
                .courseId(request.courseId())
                .name(request.name())
                .description(request.description())
                .batchType(request.batchType())
                .trainerMembershipId(request.trainerMembershipId())
                .build();
        Batch saved = batchRepository.save(batch);
        return toResponse(saved, trainerNamesFor(List.of(saved)));
    }

    @Transactional(readOnly = true)
    public List<BatchResponse> listForCourse(UUID courseId) {
        List<Batch> batches = batchRepository.findByCourseId(courseId);
        Map<UUID, String> trainerNames = trainerNamesFor(batches);
        return batches.stream().map(b -> toResponse(b, trainerNames)).collect(Collectors.toList());
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
        List<Batch> batches = batchRepository.findAllById(batchIds);
        Map<UUID, String> trainerNames = trainerNamesFor(batches);
        return batches.stream().map(b -> toResponse(b, trainerNames)).collect(Collectors.toList());
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
        batchRepository.delete(batch);
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

    /** One batched lookup instead of an N+1 per-batch query - collects every distinct trainer
     * membership referenced across the given batches, then resolves each to a display name in a
     * single pair of findAllById calls. */
    private Map<UUID, String> trainerNamesFor(List<Batch> batches) {
        Set<UUID> trainerMembershipIds = batches.stream()
                .map(Batch::getTrainerMembershipId).filter(Objects::nonNull).collect(Collectors.toSet());
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

    private BatchResponse toResponse(Batch b, Map<UUID, String> trainerNames) {
        return new BatchResponse(b.getId(), b.getCourseId(), b.getName(), b.getDescription(),
                b.getBatchType(), b.getTrainerMembershipId(), trainerNames.get(b.getTrainerMembershipId()), b.getStatus());
    }
}
