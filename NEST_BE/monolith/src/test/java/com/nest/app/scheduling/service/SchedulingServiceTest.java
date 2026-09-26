package com.nest.app.scheduling.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.scheduling.dto.AddClassInstanceRequest;
import com.nest.app.scheduling.dto.SetScheduleRequest;
import com.nest.app.scheduling.dto.SlotRequest;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.app.scheduling.repository.ScheduleRepository;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.FeatureKey;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.when;

/** A Trainer with BATCH_SCHEDULING/ATTENDANCE on one course must not be able to set a schedule or
 * add an ad-hoc class for a batch on a course they don't hold that feature on - the controller's
 * @RequiresFeature only checks the union across all their courses. */
@ExtendWith(MockitoExtension.class)
class SchedulingServiceTest {

    @Mock
    private ScheduleRepository scheduleRepository;
    @Mock
    private ClassInstanceRepository classInstanceRepository;
    @Mock
    private BatchRepository batchRepository;
    @Mock
    private CourseFeatureGuard courseFeatureGuard;

    private SchedulingService schedulingService;

    private final UUID batchId = UUID.randomUUID();
    private final UUID courseId = UUID.randomUUID();

    private void newService() {
        schedulingService = new SchedulingService(scheduleRepository, classInstanceRepository,
                batchRepository, courseFeatureGuard);
        when(batchRepository.findById(batchId))
                .thenReturn(Optional.of(Batch.builder().id(batchId).courseId(courseId).build()));
    }

    @Test
    void settingAScheduleIsRejectedWhenCallerLacksBatchSchedulingOnThisCourse() {
        newService();
        doThrow(new ForbiddenException("nope")).when(courseFeatureGuard)
                .assertCourseFeature(courseId, FeatureKey.BATCH_SCHEDULING);

        var request = new SetScheduleRequest(batchId,
                List.of(new SlotRequest(DayOfWeek.MONDAY, LocalTime.of(17, 0), LocalTime.of(18, 0))),
                LocalDate.now());

        assertThatThrownBy(() -> schedulingService.setSchedule(request))
                .isInstanceOf(ForbiddenException.class);
    }

    @Test
    void settingAScheduleSucceedsWhenCallerHoldsBatchSchedulingOnThisCourse() {
        newService();
        when(scheduleRepository.findByBatchIdAndEffectiveToIsNull(batchId)).thenReturn(List.of());
        when(scheduleRepository.save(org.mockito.ArgumentMatchers.any())).thenAnswer(inv -> {
            var s = inv.getArgument(0, com.nest.app.scheduling.entity.Schedule.class);
            s.setId(UUID.randomUUID());
            return s;
        });

        var request = new SetScheduleRequest(batchId,
                List.of(new SlotRequest(DayOfWeek.MONDAY, LocalTime.of(17, 0), LocalTime.of(18, 0))),
                LocalDate.now());

        assertThatCode(() -> schedulingService.setSchedule(request)).doesNotThrowAnyException();
    }

    @Test
    void addingAnAdHocClassIsRejectedWhenCallerLacksAttendanceOnThisCourse() {
        newService();
        doThrow(new ForbiddenException("nope")).when(courseFeatureGuard)
                .assertCourseFeature(courseId, FeatureKey.ATTENDANCE);

        var request = new AddClassInstanceRequest(LocalDate.now(), LocalTime.of(17, 0), LocalTime.of(18, 0));

        assertThatThrownBy(() -> schedulingService.addAdHocInstance(batchId, request))
                .isInstanceOf(ForbiddenException.class);
    }

    @Test
    void addingAnAdHocClassSucceedsWhenCallerHoldsAttendanceOnThisCourse() {
        newService();
        when(classInstanceRepository.existsByBatchIdAndDateAndStartTime(
                batchId, LocalDate.now(), LocalTime.of(17, 0))).thenReturn(false);
        when(classInstanceRepository.save(org.mockito.ArgumentMatchers.any()))
                .thenAnswer(inv -> inv.getArgument(0));

        var request = new AddClassInstanceRequest(LocalDate.now(), LocalTime.of(17, 0), LocalTime.of(18, 0));

        assertThatCode(() -> schedulingService.addAdHocInstance(batchId, request)).doesNotThrowAnyException();
    }
}
