package com.nest.app.attendance.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

/**
 * One marked session in a student's attendance history, joined to the date it was actually held.
 *
 * <p>Distinct from {@link AttendanceResponse}, which carries {@code markedAt} - when someone
 * pressed submit - rather than the class date. Those differ whenever attendance is corrected
 * later, and a history sorted by the former shows sessions out of order.
 *
 * <p>{@code status} is {@code PRESENT}, {@code ABSENT}, or {@code HOLIDAY} - a class that was
 * cancelled, which no one was marked for and which does not count towards attendance. Holidays are
 * only ever included in a student's own history. {@code markedByName}/{@code markedAt} say who
 * recorded the entry and when; both are null for a holiday.
 */
public record StudentAttendanceRecord(
        UUID classInstanceId,
        LocalDate date,
        LocalTime startTime,
        LocalTime endTime,
        String status,
        UUID batchId,
        String batchName,
        UUID courseId,
        String courseName,
        String note,
        String markedByName,
        Instant markedAt
) {
}
