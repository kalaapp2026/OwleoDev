package com.nest.app.enrolment.dto;

import com.nest.app.enrolment.entity.BatchStatus;
import com.nest.app.enrolment.entity.BatchType;

import java.util.UUID;

public record BatchResponse(
        UUID id,
        UUID courseId,
        String name,
        String description,
        BatchType batchType,
        UUID trainerMembershipId,
        /** Denormalised for display (e.g. a Student's "my batches" view showing who's taking the
         * class) - null if no trainer is set, same as trainerMembershipId. */
        String trainerName,
        BatchStatus status
) {
}
