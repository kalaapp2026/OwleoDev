package com.nest.app.attendance.dto;

import com.nest.app.attendance.entity.AttendanceStatus;

import java.time.Instant;
import java.util.UUID;

public record AttendanceResponse(
        UUID id, UUID classInstanceId, UUID membershipId, AttendanceStatus status,
        UUID markedBy, Instant markedAt, String note
) {
}
