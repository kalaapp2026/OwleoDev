package com.nest.app.enrolment.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchType;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.app.scheduling.repository.ScheduleRepository;
import com.nest.common.exception.ConflictException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** Covers PRD 3.6: one Regular batch per course per student, unlimited Temporary batches. */
@ExtendWith(MockitoExtension.class)
class BatchServiceTest {

    @Mock
    private BatchRepository batchRepository;
    @Mock
    private BatchMemberRepository batchMemberRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private ScheduleRepository scheduleRepository;
    @Mock
    private ClassInstanceRepository classInstanceRepository;
    @Mock
    private com.nest.app.identity.service.CourseFeatureGuard courseFeatureGuard;

    private BatchService batchService;

    private final UUID courseId = UUID.randomUUID();
    private final UUID membershipId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        batchService = new BatchService(batchRepository, batchMemberRepository, membershipRepository, userRepository,
                scheduleRepository, classInstanceRepository, courseFeatureGuard);
    }

    @Test
    void addingToASecondRegularBatchForTheSameCourseIsRejected() {
        Batch existingRegularBatch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();
        Batch targetBatch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();

        when(batchRepository.findById(targetBatch.getId())).thenReturn(java.util.Optional.of(targetBatch));
        when(batchMemberRepository.findByMembershipId(membershipId))
                .thenReturn(List.of(BatchMember.builder().batchId(existingRegularBatch.getId()).membershipId(membershipId).build()));
        when(batchRepository.findAllById(Set.of(existingRegularBatch.getId()))).thenReturn(List.of(existingRegularBatch));

        assertThatThrownBy(() -> batchService.addMember(targetBatch.getId(), membershipId))
                .isInstanceOf(ConflictException.class);

        verify(batchMemberRepository, never()).save(any());
    }

    @Test
    void studentCanJoinMultipleTemporaryBatchesFreely() {
        Batch existingRegularBatch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();
        Batch temporaryBatch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.TEMPORARY).build();

        when(batchRepository.findById(temporaryBatch.getId())).thenReturn(java.util.Optional.of(temporaryBatch));
        when(batchMemberRepository.existsByBatchIdAndMembershipId(temporaryBatch.getId(), membershipId)).thenReturn(false);

        assertThatCode(() -> batchService.addMember(temporaryBatch.getId(), membershipId)).doesNotThrowAnyException();

        verify(batchMemberRepository).save(any(BatchMember.class));
        // Temporary batches skip the cross-batch regular-membership lookup entirely.
        verify(batchMemberRepository, never()).findByMembershipId(any());
    }

    @Test
    void joiningARegularBatchForADifferentCourseIsAllowed() {
        UUID otherCourseId = UUID.randomUUID();
        Batch otherCourseRegularBatch = Batch.builder().id(UUID.randomUUID()).courseId(otherCourseId).batchType(BatchType.REGULAR).build();
        Batch targetBatch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();

        when(batchRepository.findById(targetBatch.getId())).thenReturn(java.util.Optional.of(targetBatch));
        when(batchMemberRepository.findByMembershipId(membershipId))
                .thenReturn(List.of(BatchMember.builder().batchId(otherCourseRegularBatch.getId()).membershipId(membershipId).build()));
        when(batchRepository.findAllById(Set.of(otherCourseRegularBatch.getId()))).thenReturn(List.of(otherCourseRegularBatch));
        when(batchMemberRepository.existsByBatchIdAndMembershipId(targetBatch.getId(), membershipId)).thenReturn(false);

        assertThatCode(() -> batchService.addMember(targetBatch.getId(), membershipId)).doesNotThrowAnyException();

        verify(batchMemberRepository).save(any(BatchMember.class));
    }

    @Test
    void deletingABatchWithMembersIsRejected() {
        Batch batch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();

        when(batchRepository.findById(batch.getId())).thenReturn(java.util.Optional.of(batch));
        when(batchMemberRepository.findByBatchId(batch.getId()))
                .thenReturn(List.of(BatchMember.builder().batchId(batch.getId()).membershipId(membershipId).build()));

        assertThatThrownBy(() -> batchService.delete(batch.getId()))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("de-link");

        verify(batchRepository, never()).delete(any());
    }

    @Test
    void deletingABatchWithAttendanceHistoryIsRejected() {
        Batch batch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();
        ClassInstance heldInstance = ClassInstance.builder().id(UUID.randomUUID()).batchId(batch.getId()).status(ClassInstanceStatus.HELD).build();

        when(batchRepository.findById(batch.getId())).thenReturn(java.util.Optional.of(batch));
        when(batchMemberRepository.findByBatchId(batch.getId())).thenReturn(List.of());
        when(classInstanceRepository.findByBatchId(batch.getId())).thenReturn(List.of(heldInstance));

        assertThatThrownBy(() -> batchService.delete(batch.getId()))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("attendance history");

        verify(batchRepository, never()).delete(any());
    }

    @Test
    void deletingAnEmptyBatchWithNoHistorySucceeds() {
        Batch batch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();

        when(batchRepository.findById(batch.getId())).thenReturn(java.util.Optional.of(batch));
        when(batchMemberRepository.findByBatchId(batch.getId())).thenReturn(List.of());
        when(classInstanceRepository.findByBatchId(batch.getId())).thenReturn(List.of());

        assertThatCode(() -> batchService.delete(batch.getId())).doesNotThrowAnyException();

        verify(scheduleRepository).deleteByBatchId(batch.getId());
        verify(classInstanceRepository).deleteByBatchId(batch.getId());
        verify(batchRepository).delete(batch);
    }
}
