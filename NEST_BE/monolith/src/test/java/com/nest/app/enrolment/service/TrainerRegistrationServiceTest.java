package com.nest.app.enrolment.service;

import com.nest.app.enrolment.dto.RegisterTrainerRequest;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
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
    @Mock
    private com.nest.app.identity.repository.TrainerCourseBatchRepository trainerCourseBatchRepository;
    @Mock
    private CourseFeatureGuard courseFeatureGuard;

    private TrainerRegistrationService trainerRegistrationService;

    private void newService() {
        trainerRegistrationService = new TrainerRegistrationService(identityRegistrationService, courseMapRepository,
                membershipRepository, userRepository, courseFeatureGrantRepository, courseRepository,
                membershipConfirmationService, trainerCourseBatchRepository, courseFeatureGuard);
    }

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
        newService();
        actingAsTrainerWithFeatures(Set.of(FeatureKey.ATTENDANCE, FeatureKey.BATCH_SCHEDULING));

        var request = new RegisterTrainerRequest("junior", "Junior Trainer", "9000000001", "junior@example.com",
                java.time.LocalDate.of(1995, 1, 1), null, null, null, null,
                Map.of(UUID.randomUUID(), Set.of(FeatureKey.ATTENDANCE, FeatureKey.BATCH_SCHEDULING, FeatureKey.FEES_DASHBOARD)), null, null);

        assertThatThrownBy(() -> trainerRegistrationService.registerTrainer(request))
                .isInstanceOf(ForbiddenException.class)
                .hasMessageContaining("FEES_DASHBOARD");
    }

    @Test
    void trainerCanDelegateExactlyTheirOwnFeatureSet() {
        newService();
        actingAsTrainerWithFeatures(Set.of(FeatureKey.ATTENDANCE, FeatureKey.BATCH_SCHEDULING, FeatureKey.RESCHEDULE));
        UUID guitarCourseId = UUID.randomUUID();
        // The per-course check now asks the guard, not the flat MembershipClaim.features() union -
        // this trainer holds all three on the one course they're delegating over.
        when(courseFeatureGuard.hasCourseFeature(eq(guitarCourseId), any())).thenReturn(true);

        User createdUser = User.builder().id(UUID.randomUUID()).username("junior").build();
        when(identityRegistrationService.createTrainerWithPassword(
                eq("junior"), any(), any(), any(), any(), any(), any(), any(), any(), eq(Role.TRAINER)))
                .thenReturn(new UserWithTempPassword(createdUser, "TempPass1"));
        when(identityRegistrationService.createMembership(any(), any(), any(), eq(Role.TRAINER), eq(MembershipStatus.ACTIVE), any()))
                .thenReturn(AcademyMembership.builder().id(UUID.randomUUID()).build());

        var request = new RegisterTrainerRequest("junior", "Junior Trainer", "9000000001", "junior@example.com",
                java.time.LocalDate.of(1995, 1, 1), null, null, null, null,
                Map.of(guitarCourseId, Set.of(FeatureKey.ATTENDANCE, FeatureKey.BATCH_SCHEDULING, FeatureKey.RESCHEDULE)), null, null);

        var response = trainerRegistrationService.registerTrainer(request);

        assertThat(response.courseFeatures().values().stream().flatMap(Set::stream).toList()).containsExactlyInAnyOrder(
                FeatureKey.ATTENDANCE, FeatureKey.BATCH_SCHEDULING, FeatureKey.RESCHEDULE);
    }

    @Test
    void trainerCannotDelegateAFeatureTheyHoldOnlyOnADifferentCourse() {
        newService();
        // Flat-union felt safe before this fix: this trainer really does hold ATTENDANCE, just not
        // on the course they're trying to grant it on - the exact gap PRD 3.5's cascading cap was
        // supposed to close.
        actingAsTrainerWithFeatures(Set.of(FeatureKey.ATTENDANCE));
        UUID danceCourseId = UUID.randomUUID();
        when(courseFeatureGuard.hasCourseFeature(danceCourseId, FeatureKey.ATTENDANCE)).thenReturn(false);

        var request = new RegisterTrainerRequest("junior", "Junior Trainer", "9000000001", "junior@example.com",
                java.time.LocalDate.of(1995, 1, 1), null, null, null, null,
                Map.of(danceCourseId, Set.of(FeatureKey.ATTENDANCE)), null, null);

        assertThatThrownBy(() -> trainerRegistrationService.registerTrainer(request))
                .isInstanceOf(ForbiddenException.class)
                .hasMessageContaining("ATTENDANCE");
    }

    @Test
    void listingTrainersForCourseIsRejectedWhenCallerLacksBatchCreationOnThisCourse() {
        newService();
        actingAsAcademyAdmin();
        UUID courseId = UUID.randomUUID();
        org.mockito.Mockito.doThrow(new ForbiddenException("nope")).when(courseFeatureGuard)
                .assertCourseFeature(courseId, FeatureKey.BATCH_CREATION);

        assertThatThrownBy(() -> trainerRegistrationService.listTrainersForCourse(courseId, false))
                .isInstanceOf(ForbiddenException.class);
    }

    @Test
    void academyAdminCannotDelegateNonDelegableFeatures() {
        newService();
        actingAsAcademyAdmin();

        var request = new RegisterTrainerRequest("ravi", "Ravi", "9000000002", "ravi@example.com",
                java.time.LocalDate.of(1990, 1, 1), null, null, null, null,
                Map.of(UUID.randomUUID(), Set.of(FeatureKey.COURSE_MANAGEMENT)), null, null);

        assertThatThrownBy(() -> trainerRegistrationService.registerTrainer(request))
                .isInstanceOf(ForbiddenException.class)
                .hasMessageContaining("never delegable");
    }

    @Test
    void academyAdminCanGrantAnyDelegableFeatureDespiteHoldingNoFeatureGrantsThemselves() {
        newService();
        actingAsAcademyAdmin();

        User createdUser = User.builder().id(UUID.randomUUID()).username("ravi").build();
        when(identityRegistrationService.createTrainerWithPassword(
                eq("ravi"), any(), any(), any(), any(), any(), any(), any(), any(), eq(Role.TRAINER)))
                .thenReturn(new UserWithTempPassword(createdUser, "TempPass2"));
        when(identityRegistrationService.createMembership(any(), any(), any(), eq(Role.TRAINER), eq(MembershipStatus.ACTIVE), any()))
                .thenReturn(AcademyMembership.builder().id(UUID.randomUUID()).build());

        var request = new RegisterTrainerRequest("ravi", "Ravi", "9000000002", "ravi@example.com",
                java.time.LocalDate.of(1990, 1, 1), null, null, null, null,
                Map.of(UUID.randomUUID(), Set.of(FeatureKey.FEES_ENTRY, FeatureKey.FEES_DASHBOARD)), null, null);

        var response = trainerRegistrationService.registerTrainer(request);

        assertThat(response.courseFeatures().values().stream().flatMap(Set::stream).toList())
                .containsExactlyInAnyOrder(FeatureKey.FEES_ENTRY, FeatureKey.FEES_DASHBOARD);
    }

    @Test
    void anExistingNestUserIsLinkedToThisAcademyInsteadOfBeingRejectedAsADuplicate() {
        newService();
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
                Map.of(UUID.randomUUID(), Set.of(FeatureKey.ATTENDANCE)), null, null);

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
        newService();
        actingAsAcademyAdmin();

        User existing = User.builder().id(UUID.randomUUID()).username("priya").fullName("Priya").build();
        when(identityRegistrationService.findByEmail("priya@example.com")).thenReturn(java.util.Optional.of(existing));
        when(identityRegistrationService.findMembership(eq(existing.getId()), any())).thenReturn(java.util.Optional.of(
                AcademyMembership.builder().id(UUID.randomUUID()).roleType(Role.STUDENT)
                        .status(MembershipStatus.ACTIVE).build()));

        var request = new RegisterTrainerRequest("priya_new", "Priya", "9000000009", "priya@example.com",
                java.time.LocalDate.of(1990, 1, 1), null, null, null, null,
                Map.of(UUID.randomUUID(), Set.of(FeatureKey.ATTENDANCE)), null, null);

        assertThatThrownBy(() -> trainerRegistrationService.registerTrainer(request))
                .isInstanceOf(com.nest.common.exception.BadRequestException.class)
                .hasMessageContaining("already");
    }

    @Test
    void getTrainerCardSucceedsForATrainerInTheActiveAcademy() {
        newService();
        UUID academyId = UUID.randomUUID();
        UUID callerMembershipId = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN,
                List.of(new MembershipClaim(callerMembershipId, academyId, "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of())),
                callerMembershipId));

        UUID membershipId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        AcademyMembership membership = AcademyMembership.builder()
                .id(membershipId).academyId(academyId).userId(userId).roleType(Role.TRAINER).build();
        User user = User.builder().id(userId).fullName("Kavya Iyer").phone("9800000000").email("kavya@example.com").build();
        when(membershipRepository.findById(membershipId)).thenReturn(java.util.Optional.of(membership));
        when(userRepository.findById(userId)).thenReturn(java.util.Optional.of(user));
        var details = new com.nest.app.enrolment.dto.PersonDetails(null, null, null, null, null, null,
                null, null, null, null, null, null, null, null, null, null,
                "Carnatic Vocals", null, java.time.LocalDate.of(2018, 6, 1));
        when(identityRegistrationService.personDetailsOf(user, membership)).thenReturn(details);

        var card = trainerRegistrationService.getTrainerCard(membershipId);

        assertThat(card.fullName()).isEqualTo("Kavya Iyer");
        assertThat(card.qualification()).isEqualTo("Carnatic Vocals");
        assertThat(card.joiningDate()).isEqualTo(java.time.LocalDate.of(2018, 6, 1));
    }

    @Test
    void getTrainerCardAllowsAFeaturedAcademyAdminNotJustTrainers() {
        newService();
        UUID academyId = UUID.randomUUID();
        UUID callerMembershipId = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN,
                List.of(new MembershipClaim(callerMembershipId, academyId, "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of())),
                callerMembershipId));

        UUID membershipId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        AcademyMembership membership = AcademyMembership.builder()
                .id(membershipId).academyId(academyId).userId(userId).roleType(Role.ACADEMY_ADMIN).build();
        User user = User.builder().id(userId).fullName("Ritika Shah").build();
        when(membershipRepository.findById(membershipId)).thenReturn(java.util.Optional.of(membership));
        when(userRepository.findById(userId)).thenReturn(java.util.Optional.of(user));
        when(identityRegistrationService.personDetailsOf(user, membership)).thenReturn(
                new com.nest.app.enrolment.dto.PersonDetails(null, null, null, null, null, null,
                        null, null, null, null, null, null, null, null, null, null, null, null, null));

        assertThat(trainerRegistrationService.getTrainerCard(membershipId).fullName()).isEqualTo("Ritika Shah");
    }

    @Test
    void getTrainerCardRejectsAMembershipFromAnotherAcademy() {
        newService();
        UUID callerMembershipId = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN,
                List.of(new MembershipClaim(callerMembershipId, UUID.randomUUID(), "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of())),
                callerMembershipId));

        UUID membershipId = UUID.randomUUID();
        AcademyMembership membership = AcademyMembership.builder()
                .id(membershipId).academyId(UUID.randomUUID()).userId(UUID.randomUUID()).roleType(Role.TRAINER).build();
        when(membershipRepository.findById(membershipId)).thenReturn(java.util.Optional.of(membership));

        assertThatThrownBy(() -> trainerRegistrationService.getTrainerCard(membershipId))
                .isInstanceOf(ForbiddenException.class);
    }
}
