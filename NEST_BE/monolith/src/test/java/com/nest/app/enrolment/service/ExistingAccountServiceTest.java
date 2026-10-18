package com.nest.app.enrolment.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.dto.ExistingAccountDtos.CheckResponse;
import com.nest.app.enrolment.dto.ExistingAccountDtos.VerifiedResponse;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.AccountLinkGrant;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.OtpPurpose;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.AccountLinkGrantRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.app.identity.service.OtpService;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** The up-front "this email already has an account" flow. What matters most here is what is NOT
 * revealed before the person's own code has been read back. */
@ExtendWith(MockitoExtension.class)
class ExistingAccountServiceTest {

    @Mock private IdentityRegistrationService identityRegistrationService;
    @Mock private AcademyMembershipRepository membershipRepository;
    @Mock private CourseMapRepository courseMapRepository;
    @Mock private CourseRepository courseRepository;
    @Mock private OtpService otpService;
    @Mock private NotificationService notificationService;
    @Mock private AccountLinkGrantRepository accountLinkGrantRepository;

    private ExistingAccountService service;

    private final UUID academyId = UUID.randomUUID();
    private final UUID otherAcademyId = UUID.randomUUID();
    private final UUID actorUserId = UUID.randomUUID();
    private final User person = User.builder().id(UUID.randomUUID()).username("meera").fullName("Meera Krishnan")
            .phone("9000000001").email("meera@example.com").build();

    @BeforeEach
    void setUp() {
        service = new ExistingAccountService(identityRegistrationService, membershipRepository, courseMapRepository,
                courseRepository, otpService, notificationService, accountLinkGrantRepository);
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private void actingAs(Role role, Set<String> features) {
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, academyId, "Natyalaya", role, features, Set.of());
        TenantContext.set(new NestPrincipal(actorUserId, "actor", role, List.of(claim), membershipId));
    }

    @Test
    void checkRevealsOnlyThatTheAccountExistsAndAMaskedName() {
        actingAs(Role.ACADEMY_ADMIN, Set.of());
        when(identityRegistrationService.findByEmail("meera@example.com")).thenReturn(Optional.of(person));
        when(identityRegistrationService.findMembership(person.getId(), academyId, Role.STUDENT)).thenReturn(Optional.empty());

        CheckResponse response = service.check("meera@example.com", "STUDENT");

        assertThat(response.exists()).isTrue();
        assertThat(response.maskedName()).isEqualTo("M*** K***");
        assertThat(response.alreadyAtThisAcademy()).isFalse();
        // Nothing but the answer: no profile lookups happen before the person has agreed.
        verify(courseMapRepository, never()).findByMembershipId(any());
        verify(membershipRepository, never()).findByUserId(any());
    }

    @Test
    void aStudentHereIsNotAlreadyHereAsATrainer() {
        actingAs(Role.ACADEMY_ADMIN, Set.of());
        when(identityRegistrationService.findByEmail("meera@example.com")).thenReturn(Optional.of(person));
        // The question is asked per role: there is no TRAINER membership here, whatever else they hold.
        when(identityRegistrationService.findMembership(person.getId(), academyId, Role.TRAINER))
                .thenReturn(Optional.empty());

        CheckResponse response = service.check("meera@example.com", "TRAINER");

        assertThat(response.exists()).isTrue();
        assertThat(response.alreadyAtThisAcademy()).isFalse();
    }

    @Test
    void checkOnAnUnknownEmailSaysSo() {
        actingAs(Role.ACADEMY_ADMIN, Set.of());
        when(identityRegistrationService.findByEmail("nobody@example.com")).thenReturn(Optional.empty());

        assertThat(service.check("nobody@example.com", "STUDENT").exists()).isFalse();
    }

    @Test
    void sendingTheCodePostsItToBothOfThePersonsNotificationBells() {
        actingAs(Role.ACADEMY_ADMIN, Set.of());
        when(identityRegistrationService.findByEmail("meera@example.com")).thenReturn(Optional.of(person));
        when(otpService.requestOtp("9000000001", OtpPurpose.MEMBERSHIP_CONFIRMATION, person.getId())).thenReturn("481516");

        service.sendCode("meera@example.com", "STUDENT");

        verify(notificationService).notify(eq(person.getId()), eq(NotificationModule.ERP),
                eq(NotificationType.MEMBERSHIP_CONFIRMATION), anyString(), org.mockito.ArgumentMatchers.contains("481516"),
                eq("481516"));
        verify(notificationService).notify(eq(person.getId()), eq(NotificationModule.SOCIAL),
                eq(NotificationType.MEMBERSHIP_CONFIRMATION), anyString(), org.mockito.ArgumentMatchers.contains("Natyalaya"),
                eq("481516"));
    }

    @Test
    void aTrainerWithoutTrainerRegistrationCannotLookUpSomeoneAsATrainer() {
        // Has the student feature only - so may add students, but not trainers.
        actingAs(Role.TRAINER, Set.of(FeatureKey.STUDENT_REGISTRATION));

        assertThatThrownBy(() -> service.check("meera@example.com", "TRAINER"))
                .isInstanceOf(ForbiddenException.class);
        verify(identityRegistrationService, never()).findByEmail(any());
    }

    @Test
    void aTrainerWithStudentRegistrationMayLookSomeoneUpAsAStudent() {
        actingAs(Role.TRAINER, Set.of(FeatureKey.STUDENT_REGISTRATION));
        when(identityRegistrationService.findByEmail("meera@example.com")).thenReturn(Optional.empty());

        assertThat(service.check("meera@example.com", "STUDENT").exists()).isFalse();
    }

    @Test
    void onlyStudentAndTrainerCanBeAddedThisWay() {
        actingAs(Role.ACADEMY_ADMIN, Set.of());

        assertThatThrownBy(() -> service.check("meera@example.com", "ACADEMY_ADMIN"))
                .isInstanceOf(BadRequestException.class);
    }

    @Test
    void aCodeIssuedForSomeoneElseIsRejectedAndNothingIsRevealed() {
        actingAs(Role.ACADEMY_ADMIN, Set.of());
        when(identityRegistrationService.findByEmail("meera@example.com")).thenReturn(Optional.of(person));
        // The latest outstanding code on this phone belongs to a different account.
        when(otpService.verifyOtp("9000000001", "123456", OtpPurpose.MEMBERSHIP_CONFIRMATION))
                .thenReturn(UUID.randomUUID());

        assertThatThrownBy(() -> service.verify("meera@example.com", "STUDENT", "123456"))
                .isInstanceOf(BadRequestException.class);
        verify(accountLinkGrantRepository, never()).save(any());
        verify(membershipRepository, never()).findByUserId(any());
    }

    @Test
    void aWrongCodePropagatesAndNothingIsRevealed() {
        actingAs(Role.ACADEMY_ADMIN, Set.of());
        when(identityRegistrationService.findByEmail("meera@example.com")).thenReturn(Optional.of(person));
        when(otpService.verifyOtp(any(), any(), any())).thenThrow(new BadRequestException("Incorrect OTP code"));

        assertThatThrownBy(() -> service.verify("meera@example.com", "STUDENT", "000000"))
                .isInstanceOf(BadRequestException.class).hasMessageContaining("Incorrect");
        verify(accountLinkGrantRepository, never()).save(any());
    }

    @Test
    void aVerifiedCodeUnlocksTheProfileTheMappingsAndAGrantBoundToThisAcademyAndCreator() {
        actingAs(Role.ACADEMY_ADMIN, Set.of());
        UUID danceId = UUID.randomUUID();
        UUID musicId = UUID.randomUUID();
        AcademyMembership here = AcademyMembership.builder().id(UUID.randomUUID()).userId(person.getId())
                .academyId(academyId).academyName("Natyalaya").roleType(Role.STUDENT)
                .status(MembershipStatus.ACTIVE).build();
        AcademyMembership elsewhere = AcademyMembership.builder().id(UUID.randomUUID()).userId(person.getId())
                .academyId(otherAcademyId).academyName("Sangeetha").roleType(Role.STUDENT)
                .status(MembershipStatus.ACTIVE).build();

        when(identityRegistrationService.findByEmail("meera@example.com")).thenReturn(Optional.of(person));
        when(otpService.verifyOtp("9000000001", "123456", OtpPurpose.MEMBERSHIP_CONFIRMATION)).thenReturn(person.getId());
        when(accountLinkGrantRepository.save(any())).thenAnswer(inv -> {
            AccountLinkGrant g = inv.getArgument(0);
            g.setId(UUID.randomUUID());
            return g;
        });
        // Returned out of order on purpose: this academy must still come first.
        when(membershipRepository.findByUserId(person.getId())).thenReturn(List.of(elsewhere, here));
        when(courseMapRepository.findByMembershipId(here.getId()))
                .thenReturn(List.of(CourseMap.builder().membershipId(here.getId()).courseId(danceId).build()));
        when(courseMapRepository.findByMembershipId(elsewhere.getId()))
                .thenReturn(List.of(CourseMap.builder().membershipId(elsewhere.getId()).courseId(musicId).build()));
        when(courseRepository.findAllById(any())).thenReturn(List.of(
                Course.builder().id(danceId).name("Bharatanatyam").build(),
                Course.builder().id(musicId).name("Carnatic Vocal").build()));

        VerifiedResponse response = service.verify("meera@example.com", "STUDENT", "123456");

        assertThat(response.fullName()).isEqualTo("Meera Krishnan");
        assertThat(response.phone()).isEqualTo("9000000001");
        assertThat(response.linkGrantId()).isNotNull();
        assertThat(response.enrolments()).hasSize(2);
        assertThat(response.enrolments().get(0).thisAcademy()).isTrue();
        assertThat(response.enrolments().get(0).courseNames()).containsExactly("Bharatanatyam");
        assertThat(response.enrolments().get(1).academyName()).isEqualTo("Sangeetha");
        assertThat(response.enrolments().get(1).courseNames()).containsExactly("Carnatic Vocal");

        var saved = org.mockito.ArgumentCaptor.forClass(AccountLinkGrant.class);
        verify(accountLinkGrantRepository).save(saved.capture());
        assertThat(saved.getValue().getUserId()).isEqualTo(person.getId());
        assertThat(saved.getValue().getAcademyId()).isEqualTo(academyId);
        assertThat(saved.getValue().getCreatedBy()).isEqualTo(actorUserId);
        assertThat(saved.getValue().isUsed()).isFalse();
    }

    @Test
    void maskingLeavesOnlyTheInitials() {
        assertThat(ExistingAccountService.maskName("Meera Krishnan")).isEqualTo("M*** K***");
        assertThat(ExistingAccountService.maskName("  Ravi ")).isEqualTo("R***");
        assertThat(ExistingAccountService.maskName(null)).isEmpty();
    }
}
