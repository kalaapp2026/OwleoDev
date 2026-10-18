package com.nest.app.scheduling.service;

import com.nest.app.attendance.repository.AttendanceRepository;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchType;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.enrolment.repository.BatchTrainerRepository;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.scheduling.dto.ScheduleEntryResponse;
import com.nest.app.scheduling.dto.ScheduleEntryStatus;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

/** Both halves of a reschedule must name each other's real date - the "moved in" row says where it
 * came from, the "moved out" row says where it went. */
@ExtendWith(MockitoExtension.class)
class ScheduleFeedServiceTest {

    @Mock private ClassInstanceRepository classInstanceRepository;
    @Mock private BatchRepository batchRepository;
    @Mock private BatchTrainerRepository batchTrainerRepository;
    @Mock private BatchMemberRepository batchMemberRepository;
    @Mock private CourseRepository courseRepository;
    @Mock private AcademyMembershipRepository membershipRepository;
    @Mock private UserRepository userRepository;
    @Mock private AttendanceRepository attendanceRepository;
    @Mock private CourseFeatureGuard courseFeatureGuard;

    private final UUID academyId = UUID.randomUUID();
    private final UUID courseId = UUID.randomUUID();
    private final UUID batchId = UUID.randomUUID();

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    @Test
    void aMovedInRowSaysItWasMovedFromTheOriginalDateNotItsOwn() {
        UUID membershipId = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "admin", Role.ACADEMY_ADMIN,
                List.of(new MembershipClaim(membershipId, academyId, "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of())),
                membershipId));

        LocalDate original = LocalDate.of(2026, 10, 18);
        LocalDate moved = LocalDate.of(2026, 10, 25);
        ClassInstance origin = ClassInstance.builder().id(UUID.randomUUID()).batchId(batchId)
                .date(original).startTime(LocalTime.of(9, 0)).endTime(LocalTime.of(10, 0))
                .status(ClassInstanceStatus.RESCHEDULED_CANCELLED).build();
        ClassInstance replacement = ClassInstance.builder().id(UUID.randomUUID()).batchId(batchId)
                .date(moved).startTime(LocalTime.of(9, 0)).endTime(LocalTime.of(10, 0))
                .status(ClassInstanceStatus.SCHEDULED).originalInstanceId(origin.getId()).build();

        when(courseRepository.findByAcademyIdOrderByNameAsc(academyId))
                .thenReturn(List.of(Course.builder().id(courseId).academyId(academyId).name("Bharatanatyam").build()));
        when(batchRepository.findByCourseIdIn(any())).thenReturn(List.of(Batch.builder()
                .id(batchId).courseId(courseId).name("adavu workshop").batchType(BatchType.TEMPORARY).build()));
        // Both halves are inside the requested window - the case that used to collide.
        when(classInstanceRepository.findByBatchIdInAndDateBetween(any(), any(), any()))
                .thenReturn(List.of(origin, replacement));

        var service = new ScheduleFeedService(classInstanceRepository, batchRepository, batchTrainerRepository,
                batchMemberRepository, courseRepository, membershipRepository, userRepository,
                attendanceRepository, courseFeatureGuard);

        List<ScheduleEntryResponse> rows = service.feed(original, moved, null);

        ScheduleEntryResponse movedIn = rows.stream()
                .filter(r -> r.status() == ScheduleEntryStatus.MOVED_IN).findFirst().orElseThrow();
        ScheduleEntryResponse movedOut = rows.stream()
                .filter(r -> r.status() == ScheduleEntryStatus.MOVED_OUT).findFirst().orElseThrow();

        assertThat(movedIn.movedFrom()).isEqualTo(original);
        assertThat(movedOut.movedTo()).isEqualTo(moved);
    }

    @Test
    void theAttendanceFeedIsScopedByAttendanceNotReschedule() {
        UUID membershipId = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "trainer", Role.TRAINER,
                List.of(new MembershipClaim(membershipId, academyId, "Natyalaya", Role.TRAINER, Set.of(), Set.of())),
                membershipId));

        LocalDate day = LocalDate.of(2026, 10, 19);
        ClassInstance instance = ClassInstance.builder().id(UUID.randomUUID()).batchId(batchId)
                .date(day).startTime(LocalTime.of(9, 0)).endTime(LocalTime.of(10, 0))
                .status(ClassInstanceStatus.SCHEDULED).build();

        // This trainer marks attendance on the course but may not reschedule its classes.
        when(courseFeatureGuard.visibleCourseIds(FeatureKey.ATTENDANCE)).thenReturn(Optional.of(Set.of(courseId)));
        when(courseFeatureGuard.visibleCourseIds(FeatureKey.RESCHEDULE)).thenReturn(Optional.of(Set.of()));
        when(courseRepository.findByAcademyIdOrderByNameAsc(academyId))
                .thenReturn(List.of(Course.builder().id(courseId).academyId(academyId).name("Bharatanatyam").build()));
        when(batchRepository.findByCourseIdIn(any())).thenReturn(List.of(Batch.builder()
                .id(batchId).courseId(courseId).name("Beginner").batchType(BatchType.REGULAR).build()));
        when(classInstanceRepository.findByBatchIdInAndDateBetween(any(), any(), any())).thenReturn(List.of(instance));

        var service = new ScheduleFeedService(classInstanceRepository, batchRepository, batchTrainerRepository,
                batchMemberRepository, courseRepository, membershipRepository, userRepository,
                attendanceRepository, courseFeatureGuard);

        // The Attendance screen's calendar: their course's classes are there.
        assertThat(service.feed(day, day, null, FeatureKey.ATTENDANCE)).hasSize(1);
        // The Schedule screen, scoped by Reschedule, still shows them nothing - unchanged.
        assertThat(service.feed(day, day, null)).isEmpty();
    }
}
