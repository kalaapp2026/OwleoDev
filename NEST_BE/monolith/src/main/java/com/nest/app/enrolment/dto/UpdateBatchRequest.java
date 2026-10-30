package com.nest.app.enrolment.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * Editing a batch. The batch type is not changeable: it determines how the batch's schedule and
 * rules were set up, and switching it after students are enrolled would silently re-scope history
 * that has already been attended against.
 */
public record UpdateBatchRequest(
        @NotBlank String name,
        /** The courses the batch spans, the first being its primary. Null leaves them as they are, which
         * is what a client that predates multi-course batches sends. Adding a course needs the batch
         * permission on it; dropping one is refused while a student of that course is still in the batch. */
        List<UUID> courseIds,
        String description,
        List<UUID> trainerMembershipIds,
        LocalDate startDate,
        LocalDate endDate,
        /** The complete roster. Students absent from this list are unmapped, so the form's student
         * picker round-trips as a set rather than needing separate add/remove calls. */
        List<UUID> studentMembershipIds,
        /** The Meet / Zoom / Teams link of an online class (http or https). Blank clears it. */
        @Size(max = 500) @Pattern(regexp = "^\\s*$|^\\s*https?://\\S+\\s*$", message = "must be a link starting with http:// or https://") String meetingLink
) {
}
