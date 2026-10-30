package com.nest.app.enrolment.dto;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/** A student's scheduled move between courses, named for display. */
public record CourseChangeResponse(
        UUID id,
        UUID membershipId,
        UUID fromCourseId,
        String fromCourseName,
        UUID toCourseId,
        String toCourseName,
        LocalDate effectiveOn,
        String status,
        List<String> toBatchNames
) {
}
