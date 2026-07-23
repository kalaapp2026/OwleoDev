package com.nest.app.attendance.service;

import com.nest.app.attendance.dto.AttendanceEntry;
import com.nest.app.attendance.dto.AttendanceResponse;
import com.nest.app.attendance.dto.SubmitAttendanceSheetRequest;
import com.nest.app.attendance.entity.Attendance;
import com.nest.app.attendance.repository.AttendanceRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

/** PRD 3.8. One record per (student, class-instance) - Present/Absent with an optional note. */
@Service
public class AttendanceService {

    private final AttendanceRepository attendanceRepository;

    public AttendanceService(AttendanceRepository attendanceRepository) {
        this.attendanceRepository = attendanceRepository;
    }

    @Transactional
    @Auditable(action = "ATTENDANCE_SUBMITTED", entityType = "attendance")
    public List<AttendanceResponse> submitSheet(UUID classInstanceId, SubmitAttendanceSheetRequest request) {
        UUID markedBy = TenantContext.currentUserId();
        return request.entries().stream()
                .map(entry -> upsert(classInstanceId, entry, markedBy))
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<AttendanceResponse> forClassInstance(UUID classInstanceId) {
        return attendanceRepository.findByClassInstanceId(classInstanceId).stream()
                .map(this::toResponse).collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<AttendanceResponse> historyForStudent(UUID membershipId) {
        return attendanceRepository.findByMembershipIdOrderByMarkedAtDesc(membershipId).stream()
                .map(this::toResponse).collect(Collectors.toList());
    }

    private AttendanceResponse upsert(UUID classInstanceId, AttendanceEntry entry, UUID markedBy) {
        var existing = attendanceRepository.findByClassInstanceIdAndMembershipId(classInstanceId, entry.membershipId());

        if (existing.isPresent()) {
            assertEditable(existing.get());
            Attendance record = existing.get();
            record.setStatus(entry.status());
            record.setNote(entry.note());
            record.setMarkedBy(markedBy);
            record.setMarkedAt(Instant.now());
            return toResponse(attendanceRepository.save(record));
        }

        Attendance record = Attendance.builder()
                .classInstanceId(classInstanceId)
                .membershipId(entry.membershipId())
                .status(entry.status())
                .note(entry.note())
                .markedBy(markedBy)
                .markedAt(Instant.now())
                .build();
        return toResponse(attendanceRepository.save(record));
    }

    /** "Immutable to the Trainer beyond a short edit window (e.g., same day) - Admin can always correct." */
    private void assertEditable(Attendance existing) {
        Role callerRole = TenantContext.currentMembership().roleType();
        if (callerRole == Role.ACADEMY_ADMIN) {
            return;
        }
        LocalDate markedDate = existing.getMarkedAt().atZone(ZoneId.systemDefault()).toLocalDate();
        if (!markedDate.equals(LocalDate.now())) {
            throw new ForbiddenException("This attendance record is outside the same-day edit window - ask an Academy Admin to correct it.");
        }
    }

    private AttendanceResponse toResponse(Attendance a) {
        return new AttendanceResponse(a.getId(), a.getClassInstanceId(), a.getMembershipId(), a.getStatus(),
                a.getMarkedBy(), a.getMarkedAt(), a.getNote());
    }
}
