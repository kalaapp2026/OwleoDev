package com.nest.app.enrolment.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.dto.ConfirmMembershipRequest;
import com.nest.app.enrolment.dto.CourseFeeSelection;
import com.nest.app.enrolment.dto.RegisterStudentRequest;
import com.nest.app.enrolment.dto.StudentResponse;
import com.nest.app.enrolment.dto.StudentSummaryResponse;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.OtpPurpose;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.app.identity.service.OtpService;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * PRD 3.4 Flow A (manual/walk-in), extended per PRD 7.4 to cover the multi-academy case: if the
 * EMAIL already belongs to a NEST user (email, not phone - a parent may register two children
 * under the same phone number), this never creates a duplicate account. Instead:
 * <ul>
 *   <li>that user is already visible to whoever's registering them - same academy AND (an Admin,
 *       who sees the whole academy, or a Trainer whose own course map overlaps at least one
 *       course this person is already enrolled in) - the newly picked courses are just added to
 *       their existing membership, no OTP needed;</li>
 *   <li>otherwise (a brand new academy for this person, OR the same academy but the registering
 *       Trainer has no course overlap with them yet - e.g. registered for Guitar by someone else,
 *       this Trainer only teaches Dance) - the new course(s) are staged and an OTP is sent to the
 *       person's own phone/in-app notifications; nothing grants access until
 *       {@link #confirmMembership} succeeds, so no one can silently claim an existing person as
 *       their student without that person's own consent.</li>
 * </ul>
 */
@Service
public class StudentRegistrationService {

    private final IdentityRegistrationService identityRegistrationService;
    private final CourseRepository courseRepository;
    private final OtpService otpService;
    private final CourseMapRepository courseMapRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;

    public StudentRegistrationService(IdentityRegistrationService identityRegistrationService, CourseRepository courseRepository,
                                       OtpService otpService, CourseMapRepository courseMapRepository,
                                       AcademyMembershipRepository membershipRepository, UserRepository userRepository,
                                       NotificationService notificationService) {
        this.identityRegistrationService = identityRegistrationService;
        this.courseRepository = courseRepository;
        this.otpService = otpService;
        this.courseMapRepository = courseMapRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.notificationService = notificationService;
    }

    /** Roster picker source for batch creation/editing - every ACTIVE Student membership in the
     * active academy that's mapped to this course, with a real name attached instead of a UUID. */
    @Transactional(readOnly = true)
    public List<StudentSummaryResponse> listStudentsForCourse(UUID courseId) {
        UUID academyId = TenantContext.currentAcademyId();

        Set<UUID> membershipIds = courseMapRepository.findByCourseId(courseId).stream()
                .map(CourseMap::getMembershipId).collect(Collectors.toSet());
        if (membershipIds.isEmpty()) {
            return List.of();
        }

        List<AcademyMembership> memberships = membershipRepository.findAllById(membershipIds).stream()
                .filter(m -> m.getAcademyId().equals(academyId))
                .filter(m -> m.getRoleType() == Role.STUDENT)
                .filter(m -> m.getStatus() == MembershipStatus.ACTIVE)
                .collect(Collectors.toList());

        Map<UUID, User> usersById = userRepository.findAllById(
                memberships.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        return memberships.stream()
                .map(m -> {
                    User u = usersById.get(m.getUserId());
                    return new StudentSummaryResponse(m.getId(), u.getId(), u.getUsername(), u.getFullName());
                })
                .collect(Collectors.toList());
    }

    @Transactional
    @Auditable(action = "STUDENT_REGISTERED", entityType = "user")
    public StudentResponse registerManual(RegisterStudentRequest request) {
        UUID academyId = TenantContext.currentAcademyId();
        UUID registeredBy = TenantContext.currentUserId();
        String academyName = TenantContext.currentMembership().academyName();

        Optional<User> existingUser = identityRegistrationService.findByEmail(request.email());
        Map<UUID, BigDecimal> courseFees = resolveCourseFees(request.courses());

        if (existingUser.isEmpty()) {
            User student = identityRegistrationService.createOtpOnlyUser(
                    request.username(), request.fullName(), request.phone(), request.email(),
                    request.dob(), request.address(), request.city(), request.state(), Role.STUDENT);
            AcademyMembership membership = identityRegistrationService.createMembership(
                    student.getId(), academyId, academyName, Role.STUDENT, MembershipStatus.ACTIVE, registeredBy);
            identityRegistrationService.addCourseMap(membership.getId(), courseFees);
            return new StudentResponse(student.getId(), membership.getId(), student.getUsername(), student.getFullName(), courseFees, false);
        }

        User student = existingUser.get();
        Optional<AcademyMembership> existingMembership = identityRegistrationService.findMembership(student.getId(), academyId);

        if (existingMembership.isPresent()) {
            AcademyMembership membership = existingMembership.get();
            if (isVisibleToCurrentActor(membership)) {
                identityRegistrationService.addCourseMap(membership.getId(), courseFees);
                return new StudentResponse(student.getId(), membership.getId(), student.getUsername(), student.getFullName(), courseFees, false);
            }
            identityRegistrationService.stagePendingCourseGrant(membership.getId(), courseFees);
            sendMembershipConfirmationOtp(student, membership.getId(), courseFees, academyName);
            return new StudentResponse(student.getId(), membership.getId(), student.getUsername(), student.getFullName(), courseFees, true);
        }

        // Existing NEST user, brand new academy - needs their own OTP confirmation (PRD 7.4).
        AcademyMembership membership = identityRegistrationService.createMembership(
                student.getId(), academyId, academyName, Role.STUDENT, MembershipStatus.PENDING_CONFIRMATION, registeredBy);
        identityRegistrationService.stagePendingCourseGrant(membership.getId(), courseFees);
        sendMembershipConfirmationOtp(student, membership.getId(), courseFees, academyName);

        return new StudentResponse(student.getId(), membership.getId(), student.getUsername(), student.getFullName(), courseFees, true);
    }

    /** Completes either flavour of the flow above - the student reads the OTP they received (in
     * the app's Notifications tab) back to whoever's completing the registration, confirming they
     * approve. membershipId comes from the earlier /students response, not client-typed phone. */
    @Transactional
    @Auditable(action = "STUDENT_MEMBERSHIP_CONFIRMED", entityType = "academy_membership")
    public StudentResponse confirmMembership(ConfirmMembershipRequest request) {
        AcademyMembership membership = membershipRepository.findById(request.membershipId())
                .orElseThrow(() -> new ResourceNotFoundException("Membership not found: " + request.membershipId()));
        User student = userRepository.findById(membership.getUserId())
                .orElseThrow(() -> new ResourceNotFoundException("No NEST account for this membership"));

        UUID confirmedContextId = otpService.verifyOtp(student.getPhone(), request.code(), OtpPurpose.MEMBERSHIP_CONFIRMATION);
        if (!confirmedContextId.equals(membership.getId())) {
            throw new BadRequestException("This code does not match the pending request");
        }

        AcademyMembership confirmed = identityRegistrationService.applyConfirmedCourseGrant(membership.getId());

        Map<UUID, BigDecimal> courseFees = new HashMap<>();
        courseRepository.findAllById(courseIdsFor(confirmed.getId())).forEach(c -> courseFees.put(c.getId(), c.getDefaultFee()));

        return new StudentResponse(student.getId(), confirmed.getId(), student.getUsername(), student.getFullName(), courseFees, false);
    }

    /** True when the CURRENT actor (whoever's calling /students right now) already has legitimate
     * visibility of this person: an Admin sees the whole academy; a Trainer only sees them if
     * their own course map overlaps at least one course this person is already enrolled in. */
    private boolean isVisibleToCurrentActor(AcademyMembership targetMembership) {
        MembershipClaim actor = TenantContext.currentMembership();
        if (actor.roleType() == Role.ACADEMY_ADMIN) {
            return true;
        }
        List<UUID> targetCourseIds = identityRegistrationService.courseIdsForMembership(targetMembership.getId());
        return targetCourseIds.stream().anyMatch(actor::hasCourse);
    }

    private void sendMembershipConfirmationOtp(User student, UUID membershipId, Map<UUID, BigDecimal> courseFees, String academyName) {
        String code = otpService.requestOtp(student.getPhone(), OtpPurpose.MEMBERSHIP_CONFIRMATION, membershipId);
        String courseNames = courseRepository.findAllById(courseFees.keySet()).stream()
                .map(Course::getName).collect(Collectors.joining(", "));
        notificationService.notify(student.getId(), NotificationType.MEMBERSHIP_CONFIRMATION, "Confirm your enrolment",
                "Someone at " + academyName + " wants to add you to " + courseNames
                        + ". Share this code with them to confirm it's really you: " + code,
                code);
    }

    private List<UUID> courseIdsFor(UUID membershipId) {
        return identityRegistrationService.courseIdsForMembership(membershipId);
    }

    /** Fee auto-fills from the course's default, editable per selection (PRD 3.4 worked example: combo discount). */
    private Map<UUID, BigDecimal> resolveCourseFees(List<CourseFeeSelection> selections) {
        Map<UUID, BigDecimal> result = new HashMap<>();
        for (CourseFeeSelection selection : selections) {
            if (selection.fee() != null) {
                result.put(selection.courseId(), selection.fee());
                continue;
            }
            Course course = courseRepository.findById(selection.courseId())
                    .orElseThrow(() -> new ResourceNotFoundException("Course not found: " + selection.courseId()));
            result.put(selection.courseId(), course.getDefaultFee());
        }
        return result;
    }
}
