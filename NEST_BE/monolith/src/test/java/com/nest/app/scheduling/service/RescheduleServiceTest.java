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
    @Mock
    private com.nest.app.identity.repository.AcademyMembershipRepository membershipRepository;

    private RescheduleService rescheduleService;

    private final UUID academyId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        rescheduleService = new RescheduleService(classInstanceRepository, membershipRepository);
    }

    @org.junit.jupiter.api.AfterEach
    void tearDown() {
        com.nest.common.security.TenantContext.clear();
    }

    /** Only the substitution path reads the tenant, so this is opt-in per test rather than in
     * setUp - a principal every test carries but most never touch is noise. */
    private void withAdminPrincipal() {
        var claim = new com.nest.common.security.MembershipClaim(
                UUID.randomUUID(), academyId, "Natyalaya",
                com.nest.common.security.Role.ACADEMY_ADMIN, java.util.Set.of(), java.util.Set.of());
        com.nest.common.security.TenantContext.set(new com.nest.common.security.NestPrincipal(
                UUID.randomUUID(), "meera", com.nest.common.security.Role.ACADEMY_ADMIN,
                List.of(claim), claim.membershipId()));
    }

    private ClassInstance scheduled(UUID id) {
        return ClassInstance.builder()
                .id(id).batchId(UUID.randomUUID()).date(LocalDate.of(2026, 9, 7))
                .startTime(LocalTime.of(16, 0)).endTime(LocalTime.of(17, 0))
                .status(ClassInstanceStatus.SCHEDULED)
                .build();
    }

    private void stubSaveEchoes() {
        when(classInstanceRepository.save(any(ClassInstance.class))).thenAnswer(inv -> inv.getArgument(0));
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

    // ------------------------------------------------------------------
    // Cancel / restore
    // ------------------------------------------------------------------

    @Test
    void cancellingKeepsTheRowAndRecordsWhy() {
        // The session must stay visible - a class that vanishes is indistinguishable from one
        // that was never scheduled, and students still turn up to it.
        UUID id = UUID.randomUUID();
        when(classInstanceRepository.findById(id)).thenReturn(Optional.of(scheduled(id)));
        stubSaveEchoes();

        rescheduleService.cancel(id, "Public holiday");

        ArgumentCaptor<ClassInstance> captor = ArgumentCaptor.forClass(ClassInstance.class);
        verify(classInstanceRepository).save(captor.capture());
        assertThat(captor.getValue().getStatus()).isEqualTo(ClassInstanceStatus.CANCELLED);
        assertThat(captor.getValue().getCancellationReason()).isEqualTo("Public holiday");
        verify(classInstanceRepository, org.mockito.Mockito.never()).delete(any());
    }

    @Test
    void restoringClearsTheCancellationReason() {
        // Leaving it would have the row claim it is cancelled for a reason that no longer applies.
        UUID id = UUID.randomUUID();
        ClassInstance cancelled = scheduled(id);
        cancelled.setStatus(ClassInstanceStatus.CANCELLED);
        cancelled.setCancellationReason("Weather");
        when(classInstanceRepository.findById(id)).thenReturn(Optional.of(cancelled));
        stubSaveEchoes();

        rescheduleService.restore(id);

        assertThat(cancelled.getStatus()).isEqualTo(ClassInstanceStatus.SCHEDULED);
        assertThat(cancelled.getCancellationReason()).isNull();
    }

    @Test
    void onlyACancelledClassCanBeRestored() {
        UUID id = UUID.randomUUID();
        when(classInstanceRepository.findById(id)).thenReturn(Optional.of(scheduled(id)));

        assertThatThrownBy(() -> rescheduleService.restore(id))
                .isInstanceOf(BadRequestException.class);
    }

    // ------------------------------------------------------------------
    // Instructor swap
    // ------------------------------------------------------------------

    @Test
    void swappingSetsASubstituteWithoutTouchingTheBatch() {
        withAdminPrincipal();
        UUID id = UUID.randomUUID();
        UUID substituteId = UUID.randomUUID();
        when(classInstanceRepository.findById(id)).thenReturn(Optional.of(scheduled(id)));
        when(membershipRepository.findById(substituteId)).thenReturn(Optional.of(
                com.nest.app.identity.entity.AcademyMembership.builder()
                        .id(substituteId).academyId(academyId).build()));
        stubSaveEchoes();

        rescheduleService.swapInstructor(id, substituteId, "Instructor unavailable");

        ArgumentCaptor<ClassInstance> captor = ArgumentCaptor.forClass(ClassInstance.class);
        verify(classInstanceRepository).save(captor.capture());
        // Still SCHEDULED - a substitution changes who teaches, not whether it happens.
        assertThat(captor.getValue().getStatus()).isEqualTo(ClassInstanceStatus.SCHEDULED);
        assertThat(captor.getValue().getSubstituteTrainerMembershipId()).isEqualTo(substituteId);
        assertThat(captor.getValue().getSubstitutionReason()).isEqualTo("Instructor unavailable");
    }

    @Test
    void aSubstituteFromAnotherAcademyIsRejected() {
        // Without this an admin could name a trainer they can't see, who would then render as a
        // blank name to everyone looking at the class.
        withAdminPrincipal();
        UUID id = UUID.randomUUID();
        UUID outsiderId = UUID.randomUUID();
        when(classInstanceRepository.findById(id)).thenReturn(Optional.of(scheduled(id)));
        when(membershipRepository.findById(outsiderId)).thenReturn(Optional.of(
                com.nest.app.identity.entity.AcademyMembership.builder()
                        .id(outsiderId).academyId(UUID.randomUUID()).build()));

        assertThatThrownBy(() -> rescheduleService.swapInstructor(id, outsiderId, null))
                .isInstanceOf(com.nest.common.exception.ForbiddenException.class);

        verify(classInstanceRepository, org.mockito.Mockito.never()).save(any());
    }

    @Test
    void undoingASwapClearsBothSubstituteFields() {
        UUID id = UUID.randomUUID();
        ClassInstance swapped = scheduled(id);
        swapped.setSubstituteTrainerMembershipId(UUID.randomUUID());
        swapped.setSubstitutionReason("Instructor unavailable");
        when(classInstanceRepository.findById(id)).thenReturn(Optional.of(swapped));
        stubSaveEchoes();

        rescheduleService.undoSwap(id);

        assertThat(swapped.getSubstituteTrainerMembershipId()).isNull();
        assertThat(swapped.getSubstitutionReason()).isNull();
    }

    @Test
    void undoingASwapThatIsNotThereIsRejected() {
        UUID id = UUID.randomUUID();
        when(classInstanceRepository.findById(id)).thenReturn(Optional.of(scheduled(id)));

        assertThatThrownBy(() -> rescheduleService.undoSwap(id))
                .isInstanceOf(BadRequestException.class);
    }

    // ------------------------------------------------------------------
    // Undo reschedule
    // ------------------------------------------------------------------

    @Test
    void undoingARescheduleFromEitherHalfRestoresTheOriginal() {
        UUID batchId = UUID.randomUUID();
        UUID originalId = UUID.randomUUID();
        UUID replacementId = UUID.randomUUID();

        ClassInstance original = scheduled(originalId);
        original.setBatchId(batchId);
        original.setStatus(ClassInstanceStatus.RESCHEDULED_CANCELLED);
        original.setRescheduleReason("Venue unavailable");

        ClassInstance replacement = scheduled(replacementId);
        replacement.setBatchId(batchId);
        replacement.setOriginalInstanceId(originalId);

        // Given the replacement's id - the half the client is most likely holding.
        when(classInstanceRepository.findById(replacementId)).thenReturn(Optional.of(replacement));
        when(classInstanceRepository.findById(originalId)).thenReturn(Optional.of(original));
        stubSaveEchoes();

        rescheduleService.undoReschedule(replacementId);

        verify(classInstanceRepository).delete(replacement);
        assertThat(original.getStatus()).isEqualTo(ClassInstanceStatus.SCHEDULED);
        assertThat(original.getRescheduleReason()).isNull();
    }

    @Test
    void undoingARescheduleWhoseReplacementWasAlreadyHeldIsRefused() {
        // Deleting it would erase attendance that was really taken.
        UUID batchId = UUID.randomUUID();
        UUID originalId = UUID.randomUUID();
        UUID replacementId = UUID.randomUUID();

        ClassInstance original = scheduled(originalId);
        original.setBatchId(batchId);
        original.setStatus(ClassInstanceStatus.RESCHEDULED_CANCELLED);

        ClassInstance replacement = scheduled(replacementId);
        replacement.setBatchId(batchId);
        replacement.setOriginalInstanceId(originalId);
        replacement.setStatus(ClassInstanceStatus.HELD);

        when(classInstanceRepository.findById(replacementId)).thenReturn(Optional.of(replacement));
        when(classInstanceRepository.findById(originalId)).thenReturn(Optional.of(original));

        assertThatThrownBy(() -> rescheduleService.undoReschedule(replacementId))
                .isInstanceOf(com.nest.common.exception.ConflictException.class)
                .hasMessageContaining("already been held");

        verify(classInstanceRepository, org.mockito.Mockito.never()).delete(any());
    }

    @Test
    void undoingARescheduleOnAnUntouchedClassIsRejected() {
        UUID id = UUID.randomUUID();
        ClassInstance untouched = scheduled(id);
        when(classInstanceRepository.findById(id)).thenReturn(Optional.of(untouched));
        when(classInstanceRepository.findByBatchId(untouched.getBatchId())).thenReturn(List.of(untouched));

        assertThatThrownBy(() -> rescheduleService.undoReschedule(id))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("nothing to undo");
    }
}
