package com.nest.app.enrolment.service;

import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.dto.ConfirmMembershipRequest;
import com.nest.app.enrolment.dto.CourseFeeSelection;
import com.nest.app.enrolment.dto.RegisterStudentRequest;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.OtpPurpose;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.app.identity.service.OtpService;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.exception.BadRequestException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * PRD 7.4 addendum: email (not phone) is the multi-academy dedup key, since a parent may register
 * two children under the same phone number - and OTP confirmation is only required when the
 * registering Trainer/Admin doesn't already have legitimate course-scoped visibility of the
 * person, not merely because a membership already exists in the academy.
 */
@ExtendWith(MockitoExtension.class)
class StudentRegistrationServiceTest {

    @Mock
    private IdentityRegistrationService identityRegistrationService;
    @Mock
    private CourseRepository courseRepository;
    @Mock
    private OtpService otpService;
    @Mock
    private CourseMapRepository courseMapRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private NotificationService notificationService;

    private StudentRegistrationService service;
    private final UUID academyId = UUID.randomUUID();
    private final UUID courseId = UUID.randomUUID();

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private void newService() {
        service = new StudentRegistrationService(identityRegistrationService, courseRepository, otpService,
                courseMapRepository, membershipRepository, userRepository, notificationService);
    }

    private void actingAsAdmin() {
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, academyId, "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "admin", Role.ACADEMY_ADMIN, List.of(claim), membershipId));
    }

    private void actingAsTrainerWithCourses(Set<UUID> courseIds) {
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, academyId, "Natyalaya", Role.TRAINER, Set.of(), courseIds);
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "trainer", Role.TRAINER, List.of(claim), membershipId));
    }

    private RegisterStudentRequest request(String email) {
        return new RegisterStudentRequest("student1", "New Student", "9000000001", LocalDate.of(2005, 1, 1), email,
                null, null, null, List.of(new CourseFeeSelection(courseId, BigDecimal.valueOf(500))),
                // No profile details - these tests are about the registration paths, and the
                // form fields are optional by design.
                null);
    }

    @Test
    void freshEmailCreatesANewAccountImmediately() {
        newService();
        actingAsAdmin();
        when(identityRegistrationService.findByEmail("new@example.com")).thenReturn(Optional.empty());
        User created = User.builder().id(UUID.randomUUID()).username("student1").fullName("New Student").build();
        when(identityRegistrationService.createStudentWithPassword(any(), any(), any(), any(), any(), any(), any(), any(), eq(Role.STUDENT)))
                .thenReturn(new com.nest.app.identity.service.UserWithTempPassword(created, "TempPass9"));
        when(identityRegistrationService.createMembership(any(), any(), any(), eq(Role.STUDENT), eq(MembershipStatus.ACTIVE), any()))
                .thenReturn(AcademyMembership.builder().id(UUID.randomUUID()).build());

        var response = service.registerManual(request("new@example.com"));

        assertThat(response.pendingConfirmation()).isFalse();
        assertThat(response.temporaryPassword()).isEqualTo("TempPass9");
        verify(otpService, never()).requestOtp(any(), any(), any());
        verify(notificationService, never()).notify(any(), any(), any(), any(), any(), any());
    }

    @Test
    void duplicateEmailNewAcademyStagesCoursesAndSendsInAppOtp() {
        newService();
        actingAsAdmin();
        User existing = User.builder().id(UUID.randomUUID()).username("bhuvana").fullName("Bhuvana").phone("9000000002").build();
        when(identityRegistrationService.findByEmail("bhuvana@example.com")).thenReturn(Optional.of(existing));
        when(identityRegistrationService.findMembership(existing.getId(), academyId)).thenReturn(Optional.empty());
        UUID membershipId = UUID.randomUUID();
        when(identityRegistrationService.createMembership(eq(existing.getId()), eq(academyId), any(), eq(Role.STUDENT),
                eq(MembershipStatus.PENDING_CONFIRMATION), any()))
                .thenReturn(AcademyMembership.builder().id(membershipId).build());
        when(otpService.requestOtp(eq("9000000002"), eq(OtpPurpose.MEMBERSHIP_CONFIRMATION), eq(membershipId))).thenReturn("123456");

        var response = service.registerManual(request("bhuvana@example.com"));

        assertThat(response.pendingConfirmation()).isTrue();
        verify(identityRegistrationService).stagePendingCourseGrant(eq(membershipId), anyMap());
        verify(notificationService).notify(eq(existing.getId()), eq(NotificationModule.ERP), eq(NotificationType.MEMBERSHIP_CONFIRMATION), anyString(), anyString(), eq("123456"));
    }

    @Test
    void duplicateEmailSameAcademyAdminActorBypassesOtp() {
        newService();
        actingAsAdmin();
        User existing = User.builder().id(UUID.randomUUID()).username("bhuvana").fullName("Bhuvana").phone("9000000002").build();
        when(identityRegistrationService.findByEmail("bhuvana@example.com")).thenReturn(Optional.of(existing));
        AcademyMembership membership = AcademyMembership.builder().id(UUID.randomUUID()).userId(existing.getId()).academyId(academyId).build();
        when(identityRegistrationService.findMembership(existing.getId(), academyId)).thenReturn(Optional.of(membership));

        var response = service.registerManual(request("bhuvana@example.com"));

        assertThat(response.pendingConfirmation()).isFalse();
        verify(identityRegistrationService).addCourseMap(eq(membership.getId()), anyMap());
        verify(otpService, never()).requestOtp(any(), any(), any());
    }

    @Test
    void duplicateEmailSameAcademyTrainerWithCourseOverlapBypassesOtp() {
        newService();
        UUID guitarCourseId = UUID.randomUUID();
        actingAsTrainerWithCourses(Set.of(guitarCourseId));
        User existing = User.builder().id(UUID.randomUUID()).username("bhuvana").fullName("Bhuvana").phone("9000000002").build();
        when(identityRegistrationService.findByEmail("bhuvana@example.com")).thenReturn(Optional.of(existing));
        AcademyMembership membership = AcademyMembership.builder().id(UUID.randomUUID()).userId(existing.getId()).academyId(academyId).build();
        when(identityRegistrationService.findMembership(existing.getId(), academyId)).thenReturn(Optional.of(membership));
        // Already enrolled in Guitar - the same course this Trainer teaches, so they're visible.
        when(identityRegistrationService.courseIdsForMembership(membership.getId())).thenReturn(List.of(guitarCourseId));

        var response = service.registerManual(request("bhuvana@example.com"));

        assertThat(response.pendingConfirmation()).isFalse();
        verify(identityRegistrationService).addCourseMap(eq(membership.getId()), anyMap());
        verify(otpService, never()).requestOtp(any(), any(), any());
    }

    @Test
    void duplicateEmailSameAcademyTrainerWithoutCourseOverlapStillRequiresOtp() {
        newService();
        UUID danceCourseId = UUID.randomUUID();
        actingAsTrainerWithCourses(Set.of(danceCourseId));
        User existing = User.builder().id(UUID.randomUUID()).username("bhuvana").fullName("Bhuvana").phone("9000000002").build();
        when(identityRegistrationService.findByEmail("bhuvana@example.com")).thenReturn(Optional.of(existing));
        AcademyMembership membership = AcademyMembership.builder().id(UUID.randomUUID()).userId(existing.getId()).academyId(academyId).build();
        when(identityRegistrationService.findMembership(existing.getId(), academyId)).thenReturn(Optional.of(membership));
        // Enrolled in Guitar only - this Trainer (Dance) has no overlap, so they can't already see this person.
        when(identityRegistrationService.courseIdsForMembership(membership.getId())).thenReturn(List.of(courseId));
        when(otpService.requestOtp(eq("9000000002"), eq(OtpPurpose.MEMBERSHIP_CONFIRMATION), eq(membership.getId()))).thenReturn("654321");

        var response = service.registerManual(request("bhuvana@example.com"));

        assertThat(response.pendingConfirmation()).isTrue();
        verify(identityRegistrationService).stagePendingCourseGrant(eq(membership.getId()), anyMap());
        verify(identityRegistrationService, never()).addCourseMap(any(), anyMap());
    }

    @Test
    void confirmMembershipRejectsACodeForADifferentPendingRequest() {
        newService();
        UUID membershipId = UUID.randomUUID();
        UUID otherMembershipId = UUID.randomUUID();
        User existing = User.builder().id(UUID.randomUUID()).username("bhuvana").fullName("Bhuvana").phone("9000000002").build();
        when(membershipRepository.findById(membershipId))
                .thenReturn(Optional.of(AcademyMembership.builder().id(membershipId).userId(existing.getId()).build()));
        when(userRepository.findById(existing.getId())).thenReturn(Optional.of(existing));
        when(otpService.verifyOtp("9000000002", "111111", OtpPurpose.MEMBERSHIP_CONFIRMATION)).thenReturn(otherMembershipId);

        assertThatThrownBy(() -> service.confirmMembership(new ConfirmMembershipRequest(membershipId, "111111")))
                .isInstanceOf(BadRequestException.class);

        verify(identityRegistrationService, never()).applyConfirmedCourseGrant(any());
    }

    @Test
    void confirmMembershipAppliesTheStagedGrantOnSuccess() {
        newService();
        UUID membershipId = UUID.randomUUID();
        User existing = User.builder().id(UUID.randomUUID()).username("bhuvana").fullName("Bhuvana").phone("9000000002").build();
        when(membershipRepository.findById(membershipId))
                .thenReturn(Optional.of(AcademyMembership.builder().id(membershipId).userId(existing.getId()).build()));
        when(userRepository.findById(existing.getId())).thenReturn(Optional.of(existing));
        when(otpService.verifyOtp("9000000002", "111111", OtpPurpose.MEMBERSHIP_CONFIRMATION)).thenReturn(membershipId);
        when(identityRegistrationService.applyConfirmedCourseGrant(membershipId))
                .thenReturn(AcademyMembership.builder().id(membershipId).userId(existing.getId()).status(MembershipStatus.ACTIVE).build());
        when(identityRegistrationService.courseIdsForMembership(membershipId)).thenReturn(List.of());

        var response = service.confirmMembership(new ConfirmMembershipRequest(membershipId, "111111"));

        assertThat(response.pendingConfirmation()).isFalse();
        assertThat(response.membershipId()).isEqualTo(membershipId);
    }

    @Test
    void deactivatingACourseMemberFlipsTheCourseMapActiveFlag() {
        newService();
        actingAsAdmin();
        UUID membershipId = UUID.randomUUID();
        var courseMap = com.nest.app.identity.entity.CourseMap.builder()
                .id(UUID.randomUUID()).membershipId(membershipId).courseId(courseId).active(true).build();
        when(membershipRepository.findById(membershipId))
                .thenReturn(Optional.of(AcademyMembership.builder().id(membershipId).academyId(academyId).build()));
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId)).thenReturn(Optional.of(courseMap));

        service.setCourseMemberActive(courseId, membershipId, false);

        assertThat(courseMap.isActive()).isFalse();
        verify(courseMapRepository).save(courseMap);
    }

    @Test
    void cannotToggleAMemberBelongingToAnotherAcademy() {
        newService();
        actingAsAdmin(); // active academy == academyId
        UUID membershipId = UUID.randomUUID();
        when(membershipRepository.findById(membershipId))
                .thenReturn(Optional.of(AcademyMembership.builder().id(membershipId).academyId(UUID.randomUUID()).build()));

        assertThatThrownBy(() -> service.setCourseMemberActive(courseId, membershipId, false))
                .isInstanceOf(com.nest.common.exception.ForbiddenException.class);

        verify(courseMapRepository, never()).save(any());
    }
}
