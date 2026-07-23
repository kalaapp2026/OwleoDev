package com.nest.app.calendar.dto;

import com.nest.app.scheduling.entity.ClassInstanceStatus;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

/** One calendar entry - a class instance pre-joined with the batch/course/academy names the UI
 * needs to render it directly, plus which of the caller's own memberships it came from (that's
 * the colour-coding key for a multi-academy calendar, PRD 7.5). */
public record CalendarClassResponse(
        UUID classInstanceId,
        LocalDate date,
        LocalTime startTime,
        LocalTime endTime,
        ClassInstanceStatus status,
        UUID batchId,
        String batchName,
        UUID courseId,
        String courseName,
        UUID academyId,
        String academyName,
        UUID membershipId
) {
}
