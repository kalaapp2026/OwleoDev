package com.nest.app.attendance.dto;

import com.nest.app.attendance.entity.AttendanceStatus;
import jakarta.validation.constraints.NotNull;

import java.util.UUID;

public record AttendanceEntry(@NotNull UUID membershipId, @NotNull AttendanceStatus status, String note) {
}
