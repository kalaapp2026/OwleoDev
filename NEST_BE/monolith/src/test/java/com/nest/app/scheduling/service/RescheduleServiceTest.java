package com.nest.app.scheduling.service;

import com.nest.app.scheduling.dto.RescheduleRequest;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** Covers PRD 3.7.2: the original instance is marked Cancelled-Rescheduled (never deleted) and a
 * new linked instance carries the roster forward. */
@ExtendWith(MockitoExtension.class)
class RescheduleServiceTest {

    @Mock
    private ClassInstanceRepository classInstanceRepository;

    private RescheduleService rescheduleService;

    @BeforeEach
    void setUp() {
        rescheduleService = new RescheduleService(classInstanceRepository);
    }

    @Test
    void rescheduleMarksOriginalCancelledAndCreatesLinkedReplacement() {
        UUID batchId = UUID.randomUUID();
        UUID originalId = UUID.randomUUID();
        ClassInstance original = ClassInstance.builder()
                .id(originalId).batchId(batchId).date(LocalDate.of(2026, 7, 9))
                .startTime(LocalTime.of(16, 0)).endTime(LocalTime.of(17, 0))
                .status(ClassInstanceStatus.SCHEDULED)
                .build();
        when(classInstanceRepository.findById(originalId)).thenReturn(Optional.of(original));
        when(classInstanceRepository.save(any(ClassInstance.class))).thenAnswer(inv -> {
            ClassInstance ci = inv.getArgument(0);
            if (ci.getId() == null) {
                ci.setId(UUID.randomUUID());
            }
            return ci;
        });

        var response = rescheduleService.reschedule(originalId, new RescheduleRequest(
                LocalDate.of(2026, 7, 11), LocalTime.of(17, 0), LocalTime.of(18, 0), "Trainer unavailable"));

        ArgumentCaptor<ClassInstance> captor = ArgumentCaptor.forClass(ClassInstance.class);
        verify(classInstanceRepository, times(2)).save(captor.capture());
        List<ClassInstance> saved = captor.getAllValues();

        assertThat(saved.get(0).getStatus()).isEqualTo(ClassInstanceStatus.RESCHEDULED_CANCELLED);
        assertThat(saved.get(0).getRescheduleReason()).isEqualTo("Trainer unavailable");
        assertThat(saved.get(1).getStatus()).isEqualTo(ClassInstanceStatus.SCHEDULED);
        assertThat(saved.get(1).getOriginalInstanceId()).isEqualTo(originalId);
        assertThat(response.date()).isEqualTo(LocalDate.of(2026, 7, 11));
    }

    @Test
    void cannotRescheduleAnAlreadyRescheduledInstance() {
        UUID id = UUID.randomUUID();
        ClassInstance already = ClassInstance.builder().id(id).status(ClassInstanceStatus.RESCHEDULED_CANCELLED).build();
        when(classInstanceRepository.findById(id)).thenReturn(Optional.of(already));

        assertThatThrownBy(() -> rescheduleService.reschedule(id,
                new RescheduleRequest(LocalDate.now(), LocalTime.NOON, LocalTime.NOON, "reason")))
                .isInstanceOf(BadRequestException.class);
    }

    @Test
    void unknownInstanceIsRejected() {
        UUID id = UUID.randomUUID();
        when(classInstanceRepository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> rescheduleService.reschedule(id,
                new RescheduleRequest(LocalDate.now(), LocalTime.NOON, LocalTime.NOON, "reason")))
                .isInstanceOf(ResourceNotFoundException.class);
    }
}
