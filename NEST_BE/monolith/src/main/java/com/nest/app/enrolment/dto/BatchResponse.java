package com.nest.app.enrolment.dto;

import com.nest.app.enrolment.entity.BatchStatus;
import com.nest.app.enrolment.entity.BatchType;

import java.time.LocalDate;
import java.util.List;
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
        BatchStatus status,
        LocalDate startDate,
        /** Only set on a TEMPORARY batch; null means the batch is open-ended. */
        LocalDate endDate,
        /** Every trainer on the batch, primary included. Ordered by name so the list row's
         * "Meera Krishnan, Karthik Suresh" reads the same on every load. */
        List<TrainerSummary> trainers,
        /** Live roster count. Not a stored cap - the batch form shows capacity as "however many
         * students are currently in it", so a stale number is worse than no number. */
        int studentCount
) {
    public record TrainerSummary(UUID membershipId, String name) {
    }
}
