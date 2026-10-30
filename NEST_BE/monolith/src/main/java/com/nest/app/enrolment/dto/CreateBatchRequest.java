package com.nest.app.enrolment.dto;

import com.nest.app.enrolment.entity.BatchType;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record CreateBatchRequest(
        /** The batch's course for older clients that send one. When {@link #courseIds} is present it wins
         * and this is ignored. One of the two is required - BatchService enforces that. */
        UUID courseId,
        /** Every course the batch spans, the first being its primary. A batch of Basic + Intermediate +
         * Advanced learners lists all three. */
        List<UUID> courseIds,
        @NotBlank String name,
        String description,
        @NotNull BatchType batchType,
        /** Kept for older clients that send a single trainer. When {@link #trainerMembershipIds}
         * is present it wins, and this is ignored. */
        UUID trainerMembershipId,
        /** Every trainer on the batch. The first is treated as primary. */
        List<UUID> trainerMembershipIds,
        LocalDate startDate,
        /** Required for a TEMPORARY batch and rejected on a Regular one - BatchService enforces
         * that pairing, since "temporary" without an end date is just a Regular batch. */
        LocalDate endDate,
        /** Students to enrol immediately. Each still goes through the one-Regular-batch-per-course
         * rule, so a conflicting student fails the whole create rather than being silently
         * dropped from the roster the admin just built. */
        List<UUID> studentMembershipIds,
        /** The Meet / Zoom / Teams link of an online class (http or https). Blank clears it. */
        @Size(max = 500) @Pattern(regexp = "^\\s*$|^\\s*https?://\\S+\\s*$", message = "must be a link starting with http:// or https://") String meetingLink
) {
}
