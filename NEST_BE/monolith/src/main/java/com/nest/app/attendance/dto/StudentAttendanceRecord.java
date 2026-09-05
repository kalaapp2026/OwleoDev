package com.nest.app.attendance.dto;

import com.nest.app.attendance.entity.AttendanceStatus;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

/**
 * One marked session in a student's attendance history, joined to the date it was actually held.
 *
 * <p>Distinct from {@link AttendanceResponse}, which carries {@code markedAt} - when someone
 * pressed submit - rather than the class date. Those differ whenever attendance is corrected
 * later, and a history sorted by the former shows sessions out of order.
 */
public record StudentAttendanceRecord(
        UUID classInstanceId,
        LocalDate date,
        LocalTime startTime,
        LocalTime endTime,
        AttendanceStatus status,
        UUID batchId,
        String batchName,
        UUID courseId,
        String courseName,
        String note
) {
}
