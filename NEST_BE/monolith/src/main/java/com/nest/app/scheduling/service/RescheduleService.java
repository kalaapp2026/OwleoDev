package com.nest.app.scheduling.service;

import com.nest.app.scheduling.dto.ClassInstanceResponse;
import com.nest.app.scheduling.dto.RescheduleRequest;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/**
 * PRD 3.7.2 - single-instance change to a Regular batch, distinct from the RESCHEDULE feature
 * grant that gates it (see {@link com.nest.common.security.FeatureKey#RESCHEDULE}). The original
 * instance is marked Cancelled-Rescheduled, never deleted, for audit; a new instance carries the
 * same roster forward at the new date/time, linked back via originalInstanceId.
 */
@Service
public class RescheduleService {

    private final ClassInstanceRepository classInstanceRepository;
    private final AcademyMembershipRepository membershipRepository;

    public RescheduleService(ClassInstanceRepository classInstanceRepository,
                              AcademyMembershipRepository membershipRepository) {
        this.classInstanceRepository = classInstanceRepository;
        this.membershipRepository = membershipRepository;
    }

    @Transactional
    @Auditable(action = "CLASS_RESCHEDULED", entityType = "class_instance")
    public ClassInstanceResponse reschedule(UUID classInstanceId, RescheduleRequest request) {
        ClassInstance original = classInstanceRepository.findById(classInstanceId)
                .orElseThrow(() -> new ResourceNotFoundException("Class instance not found: " + classInstanceId));

        if (original.getStatus() != ClassInstanceStatus.SCHEDULED) {
            throw new BadRequestException("Only a SCHEDULED class instance can be rescheduled (current status: " + original.getStatus() + ")");
        }

        original.setStatus(ClassInstanceStatus.RESCHEDULED_CANCELLED);
        original.setRescheduleReason(request.reason());
        classInstanceRepository.save(original);

        ClassInstance replacement = ClassInstance.builder()
                .batchId(original.getBatchId())
                .scheduleId(null)
                .date(request.newDate())
                .startTime(request.newStartTime())
                .endTime(request.newEndTime())
                .status(ClassInstanceStatus.SCHEDULED)
                .originalInstanceId(original.getId())
                .build();
        replacement = classInstanceRepository.save(replacement);

        return toResponse(replacement);
    }

    /**
     * Cancels one session. The row stays on the schedule marked cancelled, with its reason - a
     * class that silently disappears is indistinguishable from one that was never scheduled, and
     * students who turn up deserve to see why it isn't happening.
     */
    @Transactional
    @Auditable(action = "CLASS_CANCELLED", entityType = "class_instance")
    public ClassInstanceResponse cancel(UUID classInstanceId, String reason) {
        ClassInstance instance = findOrThrow(classInstanceId);
        if (instance.getStatus() != ClassInstanceStatus.SCHEDULED) {
            throw new BadRequestException("Only a scheduled class can be cancelled (current status: "
                    + instance.getStatus() + ")");
        }
        instance.setStatus(ClassInstanceStatus.CANCELLED);
        instance.setCancellationReason(reason);
        return toResponse(classInstanceRepository.save(instance));
    }

    /** Puts a cancelled session back. The reason is cleared - keeping it would leave the row
     * claiming to be cancelled for a reason that no longer applies. */
    @Transactional
    @Auditable(action = "CLASS_RESTORED", entityType = "class_instance")
    public ClassInstanceResponse restore(UUID classInstanceId) {
        ClassInstance instance = findOrThrow(classInstanceId);
        if (instance.getStatus() != ClassInstanceStatus.CANCELLED) {
            throw new BadRequestException("Only a cancelled class can be restored (current status: "
                    + instance.getStatus() + ")");
        }
        instance.setStatus(ClassInstanceStatus.SCHEDULED);
        instance.setCancellationReason(null);
        return toResponse(classInstanceRepository.save(instance));
    }

    /**
     * Assigns a substitute for one session. The batch's own trainers are untouched, so every
     * other occurrence still shows whoever normally teaches it.
     */
    @Transactional
    @Auditable(action = "CLASS_INSTRUCTOR_SWAPPED", entityType = "class_instance")
    public ClassInstanceResponse swapInstructor(UUID classInstanceId, UUID substituteMembershipId, String reason) {
        ClassInstance instance = findOrThrow(classInstanceId);
        if (instance.getStatus() != ClassInstanceStatus.SCHEDULED) {
            throw new BadRequestException("Only a scheduled class can have its instructor swapped "
                    + "(current status: " + instance.getStatus() + ")");
        }

        AcademyMembership substitute = membershipRepository.findById(substituteMembershipId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Trainer membership not found: " + substituteMembershipId));
        // Without this an admin at one academy could name a trainer from another as the
        // substitute, which would then render as a blank name to everyone who can see the class.
        if (!substitute.getAcademyId().equals(TenantContext.currentAcademyId())) {
            throw new ForbiddenException("That trainer does not belong to the active academy");
        }

        instance.setSubstituteTrainerMembershipId(substituteMembershipId);
        instance.setSubstitutionReason(reason);
        return toResponse(classInstanceRepository.save(instance));
    }

    /** Removes a substitution, handing the session back to the batch's usual trainers. */
    @Transactional
    @Auditable(action = "CLASS_SUBSTITUTION_REMOVED", entityType = "class_instance")
    public ClassInstanceResponse undoSwap(UUID classInstanceId) {
        ClassInstance instance = findOrThrow(classInstanceId);
        if (instance.getSubstituteTrainerMembershipId() == null) {
            throw new BadRequestException("This class has no substitute instructor to remove.");
        }
        instance.setSubstituteTrainerMembershipId(null);
        instance.setSubstitutionReason(null);
        return toResponse(classInstanceRepository.save(instance));
    }

    /**
     * Undoes a reschedule, given the id of <em>either</em> half - the client is showing one row
     * and shouldn't have to work out which one it holds.
     *
     * <p>The replacement is deleted rather than cancelled: it was created by the reschedule and
     * has no independent history worth keeping. If it has since been taught, though, deleting it
     * would erase real attendance, so that case is refused.
     */
    @Transactional
    @Auditable(action = "CLASS_RESCHEDULE_UNDONE", entityType = "class_instance")
    public ClassInstanceResponse undoReschedule(UUID classInstanceId) {
        ClassInstance given = findOrThrow(classInstanceId);

        final ClassInstance original;
        final ClassInstance replacement;
        if (given.getOriginalInstanceId() != null) {
            replacement = given;
            original = findOrThrow(given.getOriginalInstanceId());
        } else {
            original = given;
            replacement = classInstanceRepository.findByBatchId(given.getBatchId()).stream()
                    .filter(c -> given.getId().equals(c.getOriginalInstanceId()))
                    .findFirst()
                    .orElseThrow(() -> new BadRequestException(
                            "This class has not been rescheduled, so there is nothing to undo."));
        }

        if (original.getStatus() != ClassInstanceStatus.RESCHEDULED_CANCELLED) {
            throw new BadRequestException("This class has not been rescheduled, so there is nothing to undo.");
        }
        if (replacement.getStatus() == ClassInstanceStatus.HELD) {
            throw new ConflictException(
                    "The rescheduled class has already been held - undoing it would erase its attendance.");
        }

        classInstanceRepository.delete(replacement);
        original.setStatus(ClassInstanceStatus.SCHEDULED);
        original.setRescheduleReason(null);
        return toResponse(classInstanceRepository.save(original));
    }

    private ClassInstance findOrThrow(UUID classInstanceId) {
        return classInstanceRepository.findById(classInstanceId)
                .orElseThrow(() -> new ResourceNotFoundException("Class instance not found: " + classInstanceId));
    }

    private ClassInstanceResponse toResponse(ClassInstance c) {
        return new ClassInstanceResponse(c.getId(), c.getBatchId(), c.getDate(), c.getStartTime(), c.getEndTime(),
                c.getStatus(), c.getRescheduleReason(), c.getOriginalInstanceId());
    }
}
