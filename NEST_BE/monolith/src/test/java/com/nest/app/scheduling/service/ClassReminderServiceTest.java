package com.nest.app.scheduling.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.notification.service.NotificationTriggers;
import com.nest.app.scheduling.dto.ClassReminderResponse;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** The Dashboard's Remind button: who may press it, when it refuses, and what it records. */
@ExtendWith(MockitoExtension.class)
class ClassReminderServiceTest {

    @Mock private ClassInstanceRepository classInstanceRepository;
    @Mock private BatchRepository batchRepository;
    @Mock private CourseFeatureGuard courseFeatureGuard;
    @Mock private NotificationTriggers notificationTriggers;

    private ClassReminderService service;

    private final UUID courseId = UUID.randomUUID();
    private final UUID batchId = UUID.randomUUID();
    private final UUID instanceId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new ClassReminderService(classInstanceRepository, batchRepository, courseFeatureGuard,
                notificationTriggers);
    }

    private ClassInstance instance(ClassInstanceStatus status, LocalDate date, Instant lastReminder) {
        return ClassInstance.builder().id(instanceId).batchId(batchId).date(date)
                .startTime(LocalTime.of(17, 30)).endTime(LocalTime.of(18, 30))
                .status(status).lastReminderAt(lastReminder).build();
    }

    private void given(ClassInstance instance) {
        when(classInstanceRepository.findById(instanceId)).thenReturn(Optional.of(instance));
        when(batchRepository.findById(batchId))
                .thenReturn(Optional.of(Batch.builder().id(batchId).courseId(courseId).name("Batch A").build()));
    }

    @Test
    void remindsTheBatchAndRecordsWhenAndWhoItReached() {
        ClassInstance instance = instance(ClassInstanceStatus.SCHEDULED, LocalDate.now().plusDays(1), null);
        given(instance);
        when(notificationTriggers.classReminder(instance)).thenReturn(new NotificationTriggers.ReminderReach(12, 2));

        ClassReminderResponse response = service.remind(instanceId);

        assertThat(response.students()).isEqualTo(12);
        assertThat(response.trainers()).isEqualTo(2);
        assertThat(instance.getLastReminderAt()).isNotNull();
        verify(classInstanceRepository).save(instance);
    }

    @Test
    void needsAttendanceRescheduleOrBatchSchedulingOnTheCourse() {
        given(instance(ClassInstanceStatus.SCHEDULED, LocalDate.now().plusDays(1), null));
        doThrow(new ForbiddenException("nope")).when(courseFeatureGuard).assertAnyCourseFeature(
                courseId, FeatureKey.ATTENDANCE, FeatureKey.RESCHEDULE, FeatureKey.BATCH_SCHEDULING);

        assertThatThrownBy(() -> service.remind(instanceId)).isInstanceOf(ForbiddenException.class);
        verify(notificationTriggers, never()).classReminder(any());
    }

    @Test
    void aTrainerGivenOnlyOtherBatchesOfTheCourseIsRefused() {
        given(instance(ClassInstanceStatus.SCHEDULED, LocalDate.now().plusDays(1), null));
        doThrow(new ForbiddenException("outside your batches")).when(courseFeatureGuard)
                .assertBatchInScope(courseId, batchId);

        assertThatThrownBy(() -> service.remind(instanceId)).isInstanceOf(ForbiddenException.class);
        verify(notificationTriggers, never()).classReminder(any());
    }

    @Test
    void refusesACancelledOrMovedClass() {
        given(instance(ClassInstanceStatus.CANCELLED, LocalDate.now().plusDays(1), null));

        assertThatThrownBy(() -> service.remind(instanceId))
                .isInstanceOf(BadRequestException.class).hasMessageContaining("going ahead");
        verify(notificationTriggers, never()).classReminder(any());
    }

    @Test
    void refusesAClassLongPast() {
        given(instance(ClassInstanceStatus.SCHEDULED, LocalDate.now().minusDays(3), null));

        assertThatThrownBy(() -> service.remind(instanceId))
                .isInstanceOf(BadRequestException.class).hasMessageContaining("already happened");
    }

    @Test
    void aSecondTapWithinTheCooldownDoesNotSendAgain() {
        given(instance(ClassInstanceStatus.SCHEDULED, LocalDate.now().plusDays(1), Instant.now().minusSeconds(120)));

        assertThatThrownBy(() -> service.remind(instanceId))
                .isInstanceOf(BadRequestException.class).hasMessageContaining("went out");
        verify(notificationTriggers, never()).classReminder(any());
    }

    @Test
    void canRemindAgainOnceTheCooldownHasPassed() {
        ClassInstance instance = instance(ClassInstanceStatus.SCHEDULED, LocalDate.now().plusDays(1),
                Instant.now().minusSeconds(60 * 11));
        given(instance);
        when(notificationTriggers.classReminder(instance)).thenReturn(new NotificationTriggers.ReminderReach(3, 1));

        assertThat(service.remind(instanceId).students()).isEqualTo(3);
    }

    @Test
    void aBatchWithNobodyInItSaysSoInsteadOfPretendingToSend() {
        ClassInstance instance = instance(ClassInstanceStatus.SCHEDULED, LocalDate.now().plusDays(1), null);
        given(instance);
        when(notificationTriggers.classReminder(instance)).thenReturn(new NotificationTriggers.ReminderReach(0, 0));

        assertThatThrownBy(() -> service.remind(instanceId))
                .isInstanceOf(BadRequestException.class).hasMessageContaining("no one to remind");
        // A reminder that reached nobody must not start a cooldown.
        assertThat(instance.getLastReminderAt()).isNull();
    }

    @Test
    void unknownClassIsNotFound() {
        when(classInstanceRepository.findById(instanceId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.remind(instanceId)).isInstanceOf(ResourceNotFoundException.class);
    }
}
