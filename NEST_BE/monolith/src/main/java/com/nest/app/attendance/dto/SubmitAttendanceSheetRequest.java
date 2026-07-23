package com.nest.app.attendance.dto;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.Valid;

import java.util.List;

public record SubmitAttendanceSheetRequest(@NotEmpty @Valid List<AttendanceEntry> entries) {
}
