package com.nest.app.attendance.controller;

import com.nest.app.attendance.dto.AttendanceResponse;
import com.nest.app.attendance.dto.StudentAttendanceRecord;
import com.nest.app.attendance.dto.SubmitAttendanceSheetRequest;
import com.nest.app.attendance.service.AttendanceService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Attendance")
public class AttendanceController {

    private final AttendanceService attendanceService;

    public AttendanceController(AttendanceService attendanceService) {
        this.attendanceService = attendanceService;
    }

    @PostMapping("/class-instances/{id}/attendance")
    @RequiresFeature(FeatureKey.ATTENDANCE)
    public List<AttendanceResponse> submit(@PathVariable UUID id, @Valid @RequestBody SubmitAttendanceSheetRequest request) {
        return attendanceService.submitSheet(id, request);
    }

    @GetMapping("/class-instances/{id}/attendance")
    public List<AttendanceResponse> forClassInstance(@PathVariable UUID id) {
        return attendanceService.forClassInstance(id);
    }

    @GetMapping("/students/{membershipId}/attendance")
    public List<AttendanceResponse> history(@PathVariable UUID membershipId) {
        return attendanceService.historyForStudent(membershipId);
    }

    /** The student attendance profile: marked sessions joined to the dates they were held, so the
     * screen can group by month and let a mistake be corrected on the right day. */
    @GetMapping("/students/{membershipId}/attendance/detailed")
    public List<StudentAttendanceRecord> detailedHistory(@PathVariable UUID membershipId,
                                                          @RequestParam(required = false) UUID batchId) {
        return attendanceService.detailedHistory(membershipId, batchId);
    }
}
