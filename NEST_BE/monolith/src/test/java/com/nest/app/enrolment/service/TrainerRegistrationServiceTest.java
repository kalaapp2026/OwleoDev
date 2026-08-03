package com.nest.app.enrolment.service;

import com.nest.app.enrolment.dto.RegisterTrainerRequest;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.app.identity.service.UserWithTempPassword;
import com.nest.common.exception.ForbiddenException;
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

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Covers PRD 3.5's worked example almost verbatim: a Trainer with {ATTENDANCE, BATCH_SCHEDULING}
 * can only hand out that exact set to a sub-trainer, never a superset; an Academy Admin can grant
 * any delegable feature but never COURSE_MANAGEMENT/ABOUT_US_EDIT.
 */
@ExtendWith(MockitoExtension.class)
class TrainerRegistrationServiceTest {

    @Mock
    private IdentityRegistrationService identityRegistrationService;
    @Mock
    private CourseMapRepository courseMapRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private com.nest.app.identity.repository.CourseFeatureGrantRepository courseFeatureGrantRepository;
    @Mock
    private com.nest.app.curriculum.repository.CourseRepository courseRepository;
    @Mock
    private com.nest.app.identity.service.MembershipConfirmationService membershipConfirmationService;

    private TrainerRegistrationService trainerRegistrationService;

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private void actingAsTrainerWithFeatures(Set<String> features) {
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Natyalaya", Role.TRAINER, features, Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "ravi", Role.TRAINER, List.of(claim), membershipId));
    }

    private void actingAsAcademyAdmin() {
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN, List.of(claim), membershipId));
    }

    @Test
    void trainerCannotDelegateASuperiorFeatureSet() {
        trainerRegistrationService = new TrainerRegistrationService(identityRegistrationService, courseMapRepository,
                membershipRepository, userRepository, courseFeatureGrantRepository, courseRepository, membershipConfirmationService);
        actingAsTrainerWithFeatures(Set.of(FeatureKey.ATTENDANCE, FeatureKey.BATCH_SCHEDULING));

        var request = new RegisterTrainerRequest("junior", "Junior Trainer", "9000000001", "junior@example.com",
                java.time.LocalDate.of(1995, 1, 1), null, null, null, null,
                Map.of(UUID.randomUUID(), Set.of(FeatureKey.ATTENDANCE, FeatureKey.BATCH_SCHEDULING, FeatureKey.FEES_DASHBOARD)));

        assertThatThrownBy(() -> trainerRegistrationService.registerTrainer(request))
                .isInstanceOf(ForbiddenException.class)
                .hasMessageContaining("FEES_DASHBOARD");
    }

    @Test
    void trainerCanDelegateExactlyTheirOwnFeatureSet() {
        trainerRegistrationService = new TrainerRegistrationService(identityRegistrationService, courseMapRepository,
                membershipRepository, userRepository, courseFeatureGrantRepository, courseRepository, membershipConfirmationService);
        actingAsTrainerWithFeatures(Set.of(FeatureKey.ATTENDANCE, FeatureKey.BATCH_SCHEDULING, FeatureKey.RESCHEDULE));

        User createdUser = User.builder().id(UUID.randomUUID()).username("junior").build();
        when(identityRegistrationService.createTrainerWithPassword(
                eq("junior"), any(), any(), any(), any(), any(), any(), any(), any(), eq(Role.TRAINER)))
                .thenReturn(new UserWithTempPassword(createdUser, "TempPass1"));
        when(identityRegistrationService.createMembership(any(), any(), any(), eq(Role.TRAINER), eq(MembershipStatus.ACTIVE), any()))
                .thenReturn(AcademyMembership.builder().id(UUID.randomUUID()).build());

        var request = new RegisterTrainerRequest("junior", "Junior Trainer", "9000000001", "junior@example.com",
                java.time.LocalDate.of(1995, 1, 1), null, null, null, null,
                Map.of(UUID.randomUUID(), Set.of(FeatureKey.ATTENDANCE, FeatureKey.BATCH_SCHEDULING, FeatureKey.RESCHEDULE)));

        var response = trainerRegistrationService.registerTrainer(request);

        assertThat(response.courseFeatures().values().stream().flatMap(Set::stream).toList()).containsExactlyInAnyOrder(
                FeatureKey.ATTENDANCE, FeatureKey.BATCH_SCHEDULING, FeatureKey.RESCHEDULE);
    }

    @Test
    void academyAdminCannotDelegateNonDelegableFeatures() {
        trainerRegistrationService = new TrainerRegistrationService(identityRegistrationService, courseMapRepository,
                membershipRepository, userRepository, courseFeatureGrantRepository, courseRepository, membershipConfirmationService);
        actingAsAcademyAdmin();

        var request = new RegisterTrainerRequest("ravi", "Ravi", "9000000002", "ravi@example.com",
                java.time.LocalDate.of(1990, 1, 1), null, null, null, null,
                Map.of(UUID.randomUUID(), Set.of(FeatureKey.COURSE_MANAGEMENT)));

        assertThatThrownBy(() -> trainerRegistrationService.registerTrainer(request))
                .isInstanceOf(ForbiddenException.class)
                .hasMessageContaining("never delegable");
    }

    @Test
    void academyAdminCanGrantAnyDelegableFeatureDespiteHoldingNoFeatureGrantsThemselves() {
        trainerRegistrationService = new TrainerRegistrationService(identityRegistrationService, courseMapRepository,
                membershipRepository, userRepository, courseFeatureGrantRepository, courseRepository, membershipConfirmationService);
        actingAsAcademyAdmin();

        User createdUser = User.builder().id(UUID.randomUUID()).username("ravi").build();
        when(identityRegistrationService.createTrainerWithPassword(
                eq("ravi"), any(), any(), any(), any(), any(), any(), any(), any(), eq(Role.TRAINER)))
                .thenReturn(new UserWithTempPassword(createdUser, "TempPass2"));
        when(identityRegistrationService.createMembership(any(), any(), any(), eq(Role.TRAINER), eq(MembershipStatus.ACTIVE), any()))
                .thenReturn(AcademyMembership.builder().id(UUID.randomUUID()).build());

        var request = new RegisterTrainerRequest("ravi", "Ravi", "9000000002", "ravi@example.com",
                java.time.LocalDate.of(1990, 1, 1), null, null, null, null,
                Map.of(UUID.randomUUID(), Set.of(FeatureKey.FEES_ENTRY, FeatureKey.FEES_DASHBOARD)));

        var response = trainerRegistrationService.registerTrainer(request);

        assertThat(response.courseFeatures().values().stream().flatMap(Set::stream).toList())
                .containsExactlyInAnyOrder(FeatureKey.FEES_ENTRY, FeatureKey.FEES_DASHBOARD);
    }

    @Test
    void anExistingNestUserIsLinkedToThisAcademyInsteadOfBeingRejectedAsADuplicate() {
        trainerRegistrationService = new TrainerRegistrationService(identityRegistrationService, courseMapRepository,
                membershipRepository, userRepository, courseFeatureGrantRepository, courseRepository, membershipConfirmationService);
        actingAsAcademyAdmin();

        // Someone already on NEST - e.g. a student at a different academy.
        User existing = User.builder().id(UUID.randomUUID()).username("priya").fullName("Priya").build();
        when(identityRegistrationService.findByEmail("priya@example.com")).thenReturn(java.util.Optional.of(existing));
        when(identityRegistrationService.findMembership(eq(existing.getId()), any())).thenReturn(java.util.Optional.empty());
        when(identityRegistrationService.createMembership(any(), any(), any(), eq(Role.TRAINER),
                eq(MembershipStatus.PENDING_CONFIRMATION), any()))
                .thenReturn(AcademyMembership.builder().id(UUID.randomUUID()).build());
        when(courseRepository.findAllById(any())).thenReturn(List.of());

        var request = new RegisterTrainerRequest("priya_new", "Priya", "9000000009", "priya@example.com",
                java.time.LocalDate.of(1990, 1, 1), null, null, null, null,
                Map.of(UUID.randomUUID(), Set.of(FeatureKey.ATTENDANCE)));

        var response = trainerRegistrationService.registerTrainer(request);

        assertThat(response.pendingConfirmation()).as("needs that person's own approval").isTrue();
        assertThat(response.temporaryPassword()).as("they keep their existing password").isNull();
        assertThat(response.userId()).isEqualTo(existing.getId());
        verify(identityRegistrationService, never())
                .createTrainerWithPassword(any(), any(), any(), any(), any(), any(), any(), any(), any(), any());
        verify(membershipConfirmationService).sendConfirmation(eq(existing), any(), any(), eq("a trainer"), any());
    }

    @Test
    void someoneAlreadyInThisAcademyIsRejectedWithAClearReason() {
        trainerRegistrationService = new TrainerRegistrationService(identityRegistrationService, courseMapRepository,
                membershipRepository, userRepository, courseFeatureGrantRepository, courseRepository, membershipConfirmationService);
        actingAsAcademyAdmin();

        User existing = User.builder().id(UUID.randomUUID()).username("priya").fullName("Priya").build();
        when(identityRegistrationService.findByEmail("priya@example.com")).thenReturn(java.util.Optional.of(existing));
        when(identityRegistrationService.findMembership(eq(existing.getId()), any())).thenReturn(java.util.Optional.of(
                AcademyMembership.builder().id(UUID.randomUUID()).roleType(Role.STUDENT)
                        .status(MembershipStatus.ACTIVE).build()));

        var request = new RegisterTrainerRequest("priya_new", "Priya", "9000000009", "priya@example.com",
                java.time.LocalDate.of(1990, 1, 1), null, null, null, null,
                Map.of(UUID.randomUUID(), Set.of(FeatureKey.ATTENDANCE)));

        assertThatThrownBy(() -> trainerRegistrationService.registerTrainer(request))
                .isInstanceOf(com.nest.common.exception.BadRequestException.class)
                .hasMessageContaining("already");
    }
}
