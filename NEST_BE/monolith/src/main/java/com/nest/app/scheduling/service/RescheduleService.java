package com.nest.app.scheduling.service;

import com.nest.app.scheduling.dto.ClassInstanceResponse;
import com.nest.app.scheduling.dto.RescheduleRequest;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
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

    public RescheduleService(ClassInstanceRepository classInstanceRepository) {
        this.classInstanceRepository = classInstanceRepository;
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

    private ClassInstanceResponse toResponse(ClassInstance c) {
        return new ClassInstanceResponse(c.getId(), c.getBatchId(), c.getDate(), c.getStartTime(), c.getEndTime(),
                c.getStatus(), c.getRescheduleReason(), c.getOriginalInstanceId());
    }
}
