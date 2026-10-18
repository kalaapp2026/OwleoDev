package com.nest.app.attendance.service;

import com.nest.app.attendance.dto.AttendanceEntry;
import com.nest.app.attendance.dto.AttendanceResponse;
import com.nest.app.attendance.dto.StudentAttendanceRecord;
import com.nest.app.attendance.dto.SubmitAttendanceSheetRequest;
import com.nest.app.attendance.entity.Attendance;
import com.nest.app.attendance.entity.AttendanceStatus;
import com.nest.app.attendance.repository.AttendanceRepository;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.app.notification.service.NotificationTriggers;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
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
    private final NotificationTriggers notificationTriggers;

    public AttendanceService(AttendanceRepository attendanceRepository, ClassInstanceRepository classInstanceRepository,
                             BatchRepository batchRepository, CourseRepository courseRepository,
                             CourseFeatureGuard courseFeatureGuard, NotificationTriggers notificationTriggers) {
        this.attendanceRepository = attendanceRepository;
        this.classInstanceRepository = classInstanceRepository;
        this.batchRepository = batchRepository;
        this.courseRepository = courseRepository;
        this.courseFeatureGuard = courseFeatureGuard;
        this.notificationTriggers = notificationTriggers;
    }

    @Transactional
    @Auditable(action = "ATTENDANCE_SUBMITTED", entityType = "attendance")
    public List<AttendanceResponse> submitSheet(UUID classInstanceId, SubmitAttendanceSheetRequest request) {
        // Per-course enforcement: a Trainer must hold ATTENDANCE on the course this class belongs to
        // (class -> batch -> course), not merely on some course. Admins bypass inside the guard.
        assertCanAccessClass(classInstanceId);
        UUID markedBy = TenantContext.currentUserId();
        // Only newly-absent students are told: re-saving a sheet, or editing a note on someone
        // already marked absent, must not send the same alert twice.
        List<UUID> newlyAbsent = request.entries().stream()
                .filter(e -> e.status() == AttendanceStatus.ABSENT)
                .filter(e -> attendanceRepository.findByClassInstanceIdAndMembershipId(classInstanceId, e.membershipId())
                        .map(existing -> existing.getStatus() != AttendanceStatus.ABSENT).orElse(true))
                .map(AttendanceEntry::membershipId)
                .toList();
        List<AttendanceResponse> saved = request.entries().stream()
                .map(entry -> upsert(classInstanceId, entry, markedBy))
                .collect(Collectors.toList());
        newlyAbsent.forEach(membershipId -> notificationTriggers.attendanceAbsent(classInstanceId, membershipId));
        return saved;
    }

    /** The caller must hold ATTENDANCE on this class's course AND have this class's batch within the
     * batches they were given for it. The first alone lets a trainer limited to Batch A mark Batch B. */
    private void assertCanAccessClass(UUID classInstanceId) {
        ClassInstance instance = classInstanceRepository.findById(classInstanceId)
                .orElseThrow(() -> new ResourceNotFoundException("Class not found: " + classInstanceId));
        Batch batch = batchRepository.findById(instance.getBatchId())
                .orElseThrow(() -> new ResourceNotFoundException("Batch not found: " + instance.getBatchId()));
        courseFeatureGuard.assertCourseFeature(batch.getCourseId(), FeatureKey.ATTENDANCE);
        courseFeatureGuard.assertBatchInScope(batch.getCourseId(), batch.getId());
    }

    @Transactional(readOnly = true)
    public List<AttendanceResponse> forClassInstance(UUID classInstanceId) {
        // This is a full-roster view (every student's mark for one class) - unlike the
        // student-facing history below there is no "it's my own record" case, so only Admins and
        // a Trainer holding ATTENDANCE on this class's course may see it.
        assertCanAccessClass(classInstanceId);
        return attendanceRepository.findByClassInstanceId(classInstanceId).stream()
                .map(this::toResponse).collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<AttendanceResponse> historyForStudent(UUID membershipId) {
        List<Attendance> records = attendanceRepository.findByMembershipIdOrderByMarkedAtDesc(membershipId);
        if (records.isEmpty() || isSelf(membershipId)) {
            return records.stream().map(this::toResponse).collect(Collectors.toList());
        }

        Map<UUID, ClassScope> scopeByClassInstance = resolveScopes(records);
        Map<UUID, java.util.Optional<java.util.Set<UUID>>> batchScopes = new java.util.HashMap<>();
        return records.stream()
                .filter(r -> isVisible(scopeByClassInstance.get(r.getClassInstanceId()), batchScopes))
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    private boolean isSelf(UUID membershipId) {
        return membershipId.equals(TenantContext.currentMembershipId());
    }

    /** Where one class sits: its course, and the batch within it. */
    private record ClassScope(UUID courseId, UUID batchId) {
    }

    /** A caller who isn't looking at their own record needs ATTENDANCE on that record's course AND that
     * record's batch within the batches they were given (Admins pass automatically inside the guard).
     * A record whose class/batch/course can no longer be resolved - e.g. a hard-deleted reschedule -
     * is hidden rather than guessed at. [batchScopes] caches the per-course lookup across a list. */
    private boolean isVisible(ClassScope scope, Map<UUID, java.util.Optional<java.util.Set<UUID>>> batchScopes) {
        return scope != null && scope.courseId() != null
                && courseFeatureGuard.hasCourseFeature(scope.courseId(), FeatureKey.ATTENDANCE)
                && CourseFeatureGuard.inScope(
                        batchScopes.computeIfAbsent(scope.courseId(), courseFeatureGuard::batchScope), scope.batchId());
    }

    private Map<UUID, ClassScope> resolveScopes(List<Attendance> records) {
        Map<UUID, ClassInstance> instancesById = classInstanceRepository
                .findAllById(records.stream().map(Attendance::getClassInstanceId).collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(ClassInstance::getId, c -> c));
        Map<UUID, UUID> courseIdByBatch = batchRepository
                .findAllById(instancesById.values().stream().map(ClassInstance::getBatchId).collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(Batch::getId, Batch::getCourseId));

        Map<UUID, ClassScope> result = new java.util.HashMap<>();
        for (ClassInstance instance : instancesById.values()) {
            UUID courseId = courseIdByBatch.get(instance.getBatchId());
            if (courseId != null) {
                result.put(instance.getId(), new ClassScope(courseId, instance.getBatchId()));
            }
        }
        return result;
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
        boolean isSelf = isSelf(membershipId);
        Map<UUID, java.util.Optional<java.util.Set<UUID>>> batchScopes = new java.util.HashMap<>();

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
            if (!isSelf && !isVisible(course == null ? null : new ClassScope(course.getId(), instance.getBatchId()), batchScopes)) {
                continue;
            }

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
            // No same-day window: a trainer who holds ATTENDANCE on this course (checked in submitSheet)
            // may correct any date's record, as an academy admin can. The window refused every record
            // marked on an earlier day, so some dates in a student's history flipped and others did not
            // - and it measured "today" in the server's own zone, not the academy's. Every correction
            // still stamps who made it and when (markedBy/markedAt) and goes through the audit log.
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

    private AttendanceResponse toResponse(Attendance a) {
        return new AttendanceResponse(a.getId(), a.getClassInstanceId(), a.getMembershipId(), a.getStatus(),
                a.getMarkedBy(), a.getMarkedAt(), a.getNote());
    }
}
