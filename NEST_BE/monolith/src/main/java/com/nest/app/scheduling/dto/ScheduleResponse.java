package com.nest.app.scheduling.dto;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

public record ScheduleResponse(
        UUID id, UUID batchId, DayOfWeek dayOfWeek, LocalTime startTime, LocalTime endTime,
        LocalDate effectiveFrom, LocalDate effectiveTo
) {
}
