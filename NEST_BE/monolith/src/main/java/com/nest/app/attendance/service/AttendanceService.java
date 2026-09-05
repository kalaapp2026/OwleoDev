package com.nest.app.attendance.service;

import com.nest.app.attendance.dto.AttendanceEntry;
import com.nest.app.attendance.dto.AttendanceResponse;
import com.nest.app.attendance.dto.StudentAttendanceRecord;
import com.nest.app.attendance.dto.SubmitAttendanceSheetRequest;
import com.nest.app.attendance.entity.Attendance;
import com.nest.app.attendance.repository.AttendanceRepository;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/** PRD 3.8. One record per (student, class-instance) - Present/Absent with an optional note. */
@Service
public class AttendanceService {

    private final AttendanceRepository attendanceRepository;
    private final ClassInstanceRepository classInstanceRepository;
    private final BatchRepository batchRepository;
    private final CourseRepository courseRepository;
    private final CourseFeatureGuard courseFeatureGuard;

    public AttendanceService(AttendanceRepository attendanceRepository, ClassInstanceRepository classInstanceRepository,
                             BatchRepository batchRepository, CourseRepository courseRepository,
                             CourseFeatureGuard courseFeatureGuard) {
        this.attendanceRepository = attendanceRepository;
        this.classInstanceRepository = classInstanceRepository;
        this.batchRepository = batchRepository;
        this.courseRepository = courseRepository;
        this.courseFeatureGuard = courseFeatureGuard;
    }

    @Transactional
    @Auditable(action = "ATTENDANCE_SUBMITTED", entityType = "attendance")
    public List<AttendanceResponse> submitSheet(UUID classInstanceId, SubmitAttendanceSheetRequest request) {
        // Per-course enforcement: a Trainer must hold ATTENDANCE on the course this class belongs to
        // (class -> batch -> course), not merely on some course. Admins bypass inside the guard.
        courseFeatureGuard.assertCourseFeature(courseIdOf(classInstanceId), FeatureKey.ATTENDANCE);
        UUID markedBy = TenantContext.currentUserId();
        return request.entries().stream()
                .map(entry -> upsert(classInstanceId, entry, markedBy))
                .collect(Collectors.toList());
    }

    private UUID courseIdOf(UUID classInstanceId) {
        ClassInstance instance = classInstanceRepository.findById(classInstanceId)
                .orElseThrow(() -> new ResourceNotFoundException("Class not found: " + classInstanceId));
        Batch batch = batchRepository.findById(instance.getBatchId())
                .orElseThrow(() -> new ResourceNotFoundException("Batch not found: " + instance.getBatchId()));
        return batch.getCourseId();
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

    /**
     * A student's marked sessions joined to the dates they were held, newest first.
     *
     * <p>Sorted by class date rather than {@code markedAt}: those diverge as soon as a record is
     * corrected later, and a history ordered by when someone pressed submit shows sessions out of
     * sequence.
     *
     * @param batchId optional - null means every batch the student is in.
     */
    @Transactional(readOnly = true)
    public List<StudentAttendanceRecord> detailedHistory(UUID membershipId, UUID batchId) {
        List<Attendance> records = attendanceRepository.findByMembershipIdOrderByMarkedAtDesc(membershipId);
        if (records.isEmpty()) {
            return List.of();
        }

        Map<UUID, ClassInstance> instancesById = classInstanceRepository
                .findAllById(records.stream().map(Attendance::getClassInstanceId).collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(ClassInstance::getId, c -> c));

        Map<UUID, Batch> batchesById = batchRepository
                .findAllById(instancesById.values().stream().map(ClassInstance::getBatchId)
                        .collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(Batch::getId, b -> b));

        Map<UUID, Course> coursesById = courseRepository
                .findAllById(batchesById.values().stream().map(Batch::getCourseId)
                        .collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(Course::getId, c -> c));

        List<StudentAttendanceRecord> result = new java.util.ArrayList<>();
        for (Attendance record : records) {
            ClassInstance instance = instancesById.get(record.getClassInstanceId());
            // An attendance row whose class was hard-deleted (an undone reschedule) has nothing
            // to date itself against, so it is dropped rather than rendered without a date.
            if (instance == null) {
                continue;
            }
            Batch batch = batchesById.get(instance.getBatchId());
            if (batchId != null && !instance.getBatchId().equals(batchId)) {
                continue;
            }
            Course course = batch == null ? null : coursesById.get(batch.getCourseId());

            result.add(new StudentAttendanceRecord(
                    instance.getId(), instance.getDate(), instance.getStartTime(), instance.getEndTime(),
                    record.getStatus(),
                    instance.getBatchId(), batch == null ? null : batch.getName(),
                    course == null ? null : course.getId(), course == null ? null : course.getName(),
                    record.getNote()));
        }

        result.sort(java.util.Comparator.comparing(StudentAttendanceRecord::date).reversed()
                .thenComparing(StudentAttendanceRecord::startTime));
        return result;
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
