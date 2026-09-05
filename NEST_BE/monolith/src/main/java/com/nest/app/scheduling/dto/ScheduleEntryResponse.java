package com.nest.app.scheduling.dto;

import com.nest.app.curriculum.entity.CourseCategory;
import com.nest.app.enrolment.entity.BatchType;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.UUID;

/**
 * One row in the schedule feed - a dated class already joined to its batch, course and
 * instructors, so the client renders a row without a second round of lookups.
 *
 * <p>A rescheduled session appears twice: a {@code MOVED_OUT} entry on the original date and a
 * {@code MOVED_IN} entry on the new one. Both are shown deliberately - collapsing to just the new
 * date would make a class silently vanish from the day someone expected to find it on.
 */
public record ScheduleEntryResponse(
        /** The class instance this row is about. The two halves of a reschedule share the
         * underlying pair but are distinguished by {@link #status}. */
        UUID classInstanceId,
        LocalDate date,
        LocalTime startTime,
        LocalTime endTime,
        ScheduleEntryStatus status,

        UUID batchId,
        String batchName,
        BatchType batchType,

        UUID courseId,
        String courseName,
        CourseCategory courseCategory,
        String courseIconKey,

        /** Who is actually teaching: the substitute when there is one, the batch's own trainers
         * otherwise. */
        List<PersonRef> instructors,
        /** Only populated on a SWAPPED row - who would normally have taught it. */
        List<PersonRef> regularInstructors,

        /** Why this session was changed. Null on an untouched row. */
        String reason,
        /** On a MOVED_OUT row, where the session went. */
        LocalDate movedTo,
        /** On a MOVED_IN row, where it came from. */
        LocalDate movedFrom,

        /** Whether attendance has been taken for this session. Drives the Attendance screen's
         * Marked / Not marked chip, which is the whole reason that screen exists - finding the
         * classes nobody has marked yet. */
        boolean attendanceMarked,
        /** Roster size, so the attendance list can show "4 students" before opening the class. */
        int studentCount
) {
    public record PersonRef(UUID membershipId, String name) {
    }
}
