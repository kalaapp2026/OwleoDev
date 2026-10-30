package com.nest.app.enrolment.dto;

import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/** Schedule a student's move from one course to another. */
public record CreateCourseChangeRequest(
        @NotNull UUID fromCourseId,
        @NotNull UUID toCourseId,
        /** When the move takes effect - must be a future date. Null means the 1st of next month, so the new
         * course's fee starts from next month's slip. */
        LocalDate effectiveOn,
        /** Batches of the new course to place the student in when it takes effect. Optional. */
        List<UUID> toBatchIds
) {
}
