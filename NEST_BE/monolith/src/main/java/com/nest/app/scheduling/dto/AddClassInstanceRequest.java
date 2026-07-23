package com.nest.app.scheduling.dto;

import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;
import java.time.LocalTime;

/** An ad-hoc class, added directly from the Attendance module for a session that was never on
 * the weekly schedule (a one-off, a makeup slot no one bothered to reschedule formally, etc.) -
 * distinct from {@link SetScheduleRequest}, which materialises a whole recurring pattern. */
public record AddClassInstanceRequest(
        @NotNull LocalDate date,
        @NotNull LocalTime startTime,
        @NotNull LocalTime endTime
) {
}
