package com.nest.app.attendance.service;

import com.nest.app.attendance.dto.AttendanceEntry;
import com.nest.app.attendance.dto.SubmitAttendanceSheetRequest;
import com.nest.app.attendance.entity.Attendance;
import com.nest.app.attendance.entity.AttendanceStatus;
import com.nest.app.attendance.repository.AttendanceRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

/** Covers PRD 3.8: same-day edit window for Trainers, Admin can always correct. */
@ExtendWith(MockitoExtension.class)
class AttendanceServiceTest {

    @Mock
    private AttendanceRepository attendanceRepository;
    @Mock
    private ClassInstanceRepository classInstanceRepository;
    @Mock
    private BatchRepository batchRepository;
    @Mock
    private com.nest.app.curriculum.repository.CourseRepository courseRepository;
    @Mock
    private CourseFeatureGuard courseFeatureGuard;

    private AttendanceService attendanceService;

    private final UUID classInstanceId = UUID.randomUUID();
    private final UUID batchId = UUID.randomUUID();
    private final UUID courseId = UUID.randomUUID();
    private final UUID membershipId = UUID.randomUUID();

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    /** Builds the service and stubs the class -> batch -> course resolution submitSheet now does
     * (the CourseFeatureGuard itself is a no-op mock, so it never blocks these tests). */
    private void newService() {
        attendanceService = new AttendanceService(attendanceRepository, classInstanceRepository, batchRepository, courseRepository, courseFeatureGuard);
        when(classInstanceRepository.findById(classInstanceId))
                .thenReturn(Optional.of(ClassInstance.builder().id(classInstanceId).batchId(batchId).build()));
        when(batchRepository.findById(batchId))
                .thenReturn(Optional.of(Batch.builder().id(batchId).courseId(courseId).build()));
    }

    private void actingAs(Role roleType) {
        UUID actorMembershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(actorMembershipId, UUID.randomUUID(), "Natyalaya", roleType, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "actor", roleType, List.of(claim), actorMembershipId));
    }

    @Test
    void trainerCannotEditYesterdaysAttendance() {
        newService();
        actingAs(Role.TRAINER);

        Attendance yesterday = Attendance.builder().id(UUID.randomUUID()).classInstanceId(classInstanceId)
                .membershipId(membershipId).status(AttendanceStatus.PRESENT)
                .markedAt(Instant.now().minus(1, ChronoUnit.DAYS)).build();
        when(attendanceRepository.findByClassInstanceIdAndMembershipId(classInstanceId, membershipId))
                .thenReturn(Optional.of(yesterday));

        var sheet = new SubmitAttendanceSheetRequest(List.of(new AttendanceEntry(membershipId, AttendanceStatus.ABSENT, null)));

        assertThatThrownBy(() -> attendanceService.submitSheet(classInstanceId, sheet))
                .isInstanceOf(ForbiddenException.class);
    }

    @Test
    void adminCanEditAttendanceFromAnyDay() {
        newService();
        actingAs(Role.ACADEMY_ADMIN);

        Attendance yesterday = Attendance.builder().id(UUID.randomUUID()).classInstanceId(classInstanceId)
                .membershipId(membershipId).status(AttendanceStatus.PRESENT)
                .markedAt(Instant.now().minus(3, ChronoUnit.DAYS)).build();
        when(attendanceRepository.findByClassInstanceIdAndMembershipId(classInstanceId, membershipId))
                .thenReturn(Optional.of(yesterday));
        when(attendanceRepository.save(any(Attendance.class))).thenAnswer(inv -> inv.getArgument(0));

        var sheet = new SubmitAttendanceSheetRequest(List.of(new AttendanceEntry(membershipId, AttendanceStatus.ABSENT, "corrected")));

        assertThatCode(() -> attendanceService.submitSheet(classInstanceId, sheet)).doesNotThrowAnyException();
    }

    @Test
    void trainerCanEditWithinTheSameDay() {
        newService();
        actingAs(Role.TRAINER);

        Attendance today = Attendance.builder().id(UUID.randomUUID()).classInstanceId(classInstanceId)
                .membershipId(membershipId).status(AttendanceStatus.ABSENT).markedAt(Instant.now()).build();
        when(attendanceRepository.findByClassInstanceIdAndMembershipId(classInstanceId, membershipId))
                .thenReturn(Optional.of(today));
        when(attendanceRepository.save(any(Attendance.class))).thenAnswer(inv -> inv.getArgument(0));

        var sheet = new SubmitAttendanceSheetRequest(List.of(new AttendanceEntry(membershipId, AttendanceStatus.PRESENT, null)));

        assertThatCode(() -> attendanceService.submitSheet(classInstanceId, sheet)).doesNotThrowAnyException();
    }
}
