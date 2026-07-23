package com.nest.app.scheduling.dto;

import com.nest.app.scheduling.entity.ClassInstanceStatus;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

public record ClassInstanceResponse(
        UUID id, UUID batchId, LocalDate date, LocalTime startTime, LocalTime endTime,
        ClassInstanceStatus status, String rescheduleReason, UUID originalInstanceId
) {
}
