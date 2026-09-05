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
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
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
    private com.nest.app.enrolment.repository.BatchTrainerRepository batchTrainerRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private com.nest.app.curriculum.repository.CourseRepository courseRepository;
    @Mock
    private ScheduleRepository scheduleRepository;
    @Mock
    private ClassInstanceRepository classInstanceRepository;
    @Mock
    private com.nest.app.curriculum.repository.StudyMaterialRepository studyMaterialRepository;
    @Mock
    private com.nest.app.identity.service.CourseFeatureGuard courseFeatureGuard;

    private BatchService batchService;

    private final UUID courseId = UUID.randomUUID();
    private final UUID membershipId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        batchService = new BatchService(batchRepository, batchMemberRepository, batchTrainerRepository,
                membershipRepository, userRepository, courseRepository,
                scheduleRepository, classInstanceRepository, studyMaterialRepository, courseFeatureGuard);
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
        verify(batchTrainerRepository).deleteByBatchId(batch.getId());
        verify(batchRepository).delete(batch);
    }

    // ------------------------------------------------------------------
    // Dates. A temporary batch is defined by its window; a regular one has none.
    // ------------------------------------------------------------------

    private com.nest.app.enrolment.dto.CreateBatchRequest createRequest(
            BatchType type, java.time.LocalDate start, java.time.LocalDate end) {
        return new com.nest.app.enrolment.dto.CreateBatchRequest(
                courseId, "Batch A", null, type, null, List.of(), start, end, List.of());
    }

    @Test
    void aTemporaryBatchWithoutAnEndDateIsRejected() {
        // Without an end date it would never stop generating classes, which is precisely the
        // thing that distinguishes it from a regular batch.
        assertThatThrownBy(() -> batchService.create(
                createRequest(BatchType.TEMPORARY, java.time.LocalDate.of(2026, 9, 1), null)))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("start and an end date");

        verify(batchRepository, never()).save(any());
    }

    @Test
    void aTemporaryBatchEndingBeforeItStartsIsRejected() {
        assertThatThrownBy(() -> batchService.create(createRequest(BatchType.TEMPORARY,
                java.time.LocalDate.of(2026, 10, 1), java.time.LocalDate.of(2026, 9, 1))))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("on or after");

        verify(batchRepository, never()).save(any());
    }

    @Test
    void aRegularBatchGivenAnEndDateIsRejectedRatherThanSilentlyDropped() {
        // Discarding it would leave the admin believing the batch stops on that date when it
        // never will.
        assertThatThrownBy(() -> batchService.create(createRequest(BatchType.REGULAR,
                java.time.LocalDate.of(2026, 9, 1), java.time.LocalDate.of(2026, 12, 1))))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("cannot have an end date");

        verify(batchRepository, never()).save(any());
    }

    @Test
    void theFirstTrainerInTheListBecomesThePrimary() {
        UUID lead = UUID.randomUUID();
        UUID accompanist = UUID.randomUUID();
        when(batchRepository.save(any(Batch.class))).thenAnswer(inv -> {
            Batch b = inv.getArgument(0);
            b.setId(UUID.randomUUID());
            return b;
        });
        when(batchTrainerRepository.findByBatchIdIn(any())).thenReturn(List.of());
        when(batchMemberRepository.findByBatchIdIn(any())).thenReturn(List.of());

        batchService.create(new com.nest.app.enrolment.dto.CreateBatchRequest(
                courseId, "Batch A", null, BatchType.REGULAR, null,
                // Duplicated deliberately: de-duplication must not let the repeat displace the
                // lead as primary.
                List.of(lead, accompanist, lead), java.time.LocalDate.of(2026, 9, 1), null, List.of()));

        org.mockito.ArgumentCaptor<Batch> saved = org.mockito.ArgumentCaptor.forClass(Batch.class);
        verify(batchRepository).save(saved.capture());
        assertThat(saved.getValue().getTrainerMembershipId()).isEqualTo(lead);

        // Both trainers linked, the duplicate collapsed.
        org.mockito.ArgumentCaptor<com.nest.app.enrolment.entity.BatchTrainer> links =
                org.mockito.ArgumentCaptor.forClass(com.nest.app.enrolment.entity.BatchTrainer.class);
        verify(batchTrainerRepository, org.mockito.Mockito.times(2)).save(links.capture());
        assertThat(links.getAllValues())
                .extracting(com.nest.app.enrolment.entity.BatchTrainer::getTrainerMembershipId)
                .containsExactly(lead, accompanist);
    }
}
