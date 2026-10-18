package com.nest.app.enrolment.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.dto.ExistingAccountDtos.CheckResponse;
import com.nest.app.enrolment.dto.ExistingAccountDtos.Enrolment;
import com.nest.app.enrolment.dto.ExistingAccountDtos.VerifiedResponse;
import com.nest.app.identity.entity.AccountLinkGrant;
import com.nest.app.identity.entity.AcademyMembership;
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
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Adding someone who already has a NEST account to another academy, confirmed up front.
 *
 * <p>The person - not the academy adding them - has to agree (PRD 7.4), and the agreement is made
 * visible to the creator in three steps: {@link #check} says an account exists (and nothing more),
 * {@link #sendCode} posts a code to the person's own notifications, and {@link #verify} takes the
 * code they read back and only THEN reveals their details and where they are already mapped.
 * Revealing the profile earlier would let anyone who knows an email read a stranger's phone, date of
 * birth, address and enrolments at other academies.
 *
 * <p>A successful verify records an {@link AccountLinkGrant}; registration presents it and is
 * activated on the spot. Without one, registration falls back to the older pending-membership path.
 */
@Service
public class ExistingAccountService {

    /** Long enough to finish the rest of the form after verifying; short enough not to linger. */
    private static final Duration GRANT_TTL = Duration.ofMinutes(30);

    private final IdentityRegistrationService identityRegistrationService;
    private final AcademyMembershipRepository membershipRepository;
    private final CourseMapRepository courseMapRepository;
    private final CourseRepository courseRepository;
    private final OtpService otpService;
    private final NotificationService notificationService;
    private final AccountLinkGrantRepository accountLinkGrantRepository;

    public ExistingAccountService(IdentityRegistrationService identityRegistrationService,
                                  AcademyMembershipRepository membershipRepository,
                                  CourseMapRepository courseMapRepository, CourseRepository courseRepository,
                                  OtpService otpService, NotificationService notificationService,
                                  AccountLinkGrantRepository accountLinkGrantRepository) {
        this.identityRegistrationService = identityRegistrationService;
        this.membershipRepository = membershipRepository;
        this.courseMapRepository = courseMapRepository;
        this.courseRepository = courseRepository;
        this.otpService = otpService;
        this.notificationService = notificationService;
        this.accountLinkGrantRepository = accountLinkGrantRepository;
    }

    @Transactional(readOnly = true)
    public CheckResponse check(String email, String roleName) {
        Role role = parseRole(roleName);
        requireMayAdd(role);
        Optional<User> existing = identityRegistrationService.findByEmail(email);
        if (existing.isEmpty()) {
            return new CheckResponse(false, null, false, null);
        }
        // "Already here" means already here IN THIS ROLE: a student at this academy can still be
        // added as a trainer (and the reverse), so the question is about the role being added.
        Optional<AcademyMembership> here = identityRegistrationService
                .findMembership(existing.get().getId(), TenantContext.currentAcademyId(), role);
        return new CheckResponse(true, maskName(existing.get().getFullName()), here.isPresent(),
                here.map(m -> m.getRoleType().name()).orElse(null));
    }

    @Transactional
    public void sendCode(String email, String roleName) {
        Role role = parseRole(roleName);
        requireMayAdd(role);
        User person = requireAccount(email);
        MembershipClaim actor = TenantContext.currentMembership();

        // Context is the person, not a membership: nothing exists yet for them at this academy.
        // The membership-confirmation path compares its context to a MEMBERSHIP id, so a code issued
        // here can't be replayed to activate one, and the reverse.
        String code = otpService.requestOtp(person.getPhone(), OtpPurpose.MEMBERSHIP_CONFIRMATION, person.getId());
        String title = "Confirm your enrolment";
        String body = actor.academyName() + " wants to add you as " + (role == Role.TRAINER ? "a trainer" : "a student")
                + ". Share this code with them to confirm it's really you: " + code;

        // Both bells, as the existing confirmation does: this person may have no way into the ERP side
        // at all, so an ERP-only notice would be invisible in exactly the case it exists for.
        notificationService.notify(person.getId(), NotificationModule.ERP, NotificationType.MEMBERSHIP_CONFIRMATION,
                title, body, code);
        notificationService.notify(person.getId(), NotificationModule.SOCIAL, NotificationType.MEMBERSHIP_CONFIRMATION,
                title, body, code);
    }

    @Transactional
    public VerifiedResponse verify(String email, String roleName, String code) {
        Role role = parseRole(roleName);
        requireMayAdd(role);
        User person = requireAccount(email);

        UUID issuedFor = otpService.verifyOtp(person.getPhone(), code, OtpPurpose.MEMBERSHIP_CONFIRMATION);
        if (!person.getId().equals(issuedFor)) {
            throw new BadRequestException("That code was not sent for this account");
        }

        UUID academyId = TenantContext.currentAcademyId();
        AccountLinkGrant grant = accountLinkGrantRepository.save(AccountLinkGrant.builder()
                .userId(person.getId())
                .academyId(academyId)
                .createdBy(TenantContext.currentUserId())
                .expiresAt(Instant.now().plus(GRANT_TTL))
                .build());

        List<AcademyMembership> memberships = membershipRepository.findByUserId(person.getId()).stream()
                .filter(m -> m.getStatus() == MembershipStatus.ACTIVE)
                .toList();
        // This academy's membership in the role being added, for its joining date and salary - not
        // whichever of their memberships here happens to come first.
        AcademyMembership here = memberships.stream()
                .filter(m -> m.getAcademyId().equals(academyId) && m.getRoleType() == role)
                .findFirst().orElse(null);

        return new VerifiedResponse(grant.getId(), person.getId(), person.getUsername(), person.getFullName(),
                person.getPhone(), person.getEmail(), person.getDob(),
                identityRegistrationService.personDetailsOf(person, here),
                enrolmentsOf(memberships, academyId));
    }

    /** Every academy the person is active at, with the courses they are mapped to there - this
     * academy first, since those are the mappings the creator is about to add to. */
    private List<Enrolment> enrolmentsOf(List<AcademyMembership> memberships, UUID academyId) {
        Map<UUID, List<CourseMap>> mapsByMembership = memberships.stream().collect(Collectors.toMap(
                AcademyMembership::getId,
                m -> courseMapRepository.findByMembershipId(m.getId()).stream().filter(CourseMap::isActive).toList()));
        Map<UUID, Course> coursesById = courseRepository.findAllById(
                mapsByMembership.values().stream().flatMap(List::stream).map(CourseMap::getCourseId)
                        .collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(Course::getId, c -> c));

        return memberships.stream()
                .sorted((a, b) -> Boolean.compare(b.getAcademyId().equals(academyId), a.getAcademyId().equals(academyId)))
                .map(m -> {
                    List<CourseMap> maps = mapsByMembership.get(m.getId());
                    List<UUID> ids = maps.stream().map(CourseMap::getCourseId)
                            .filter(coursesById::containsKey).toList();
                    return new Enrolment(m.getAcademyName(), m.getAcademyId().equals(academyId),
                            m.getRoleType().name(), ids,
                            ids.stream().map(id -> coursesById.get(id).getName()).toList());
                })
                .toList();
    }

    private User requireAccount(String email) {
        return identityRegistrationService.findByEmail(email)
                .orElseThrow(() -> new ResourceNotFoundException("No NEST account uses that email"));
    }

    /** Only STUDENT and TRAINER can be added this way - the two roles the registration forms create. */
    private Role parseRole(String roleName) {
        Role role;
        try {
            role = Role.valueOf(roleName == null ? "" : roleName.trim().toUpperCase());
        } catch (IllegalArgumentException e) {
            throw new BadRequestException("Role must be STUDENT or TRAINER");
        }
        if (role != Role.STUDENT && role != Role.TRAINER) {
            throw new BadRequestException("Role must be STUDENT or TRAINER");
        }
        return role;
    }

    /** The lookup reveals an account's details, so it needs the same permission as the registration
     * it serves - a trainer who can register students must not be able to look people up as trainers. */
    private void requireMayAdd(Role role) {
        MembershipClaim actor = TenantContext.currentMembership();
        if (actor.roleType() == Role.ACADEMY_ADMIN) {
            return;
        }
        String needed = role == Role.TRAINER ? FeatureKey.TRAINER_REGISTRATION : FeatureKey.STUDENT_REGISTRATION;
        if (!actor.hasFeature(needed)) {
            throw new ForbiddenException("You do not have permission to add a " + role.name().toLowerCase() + ".");
        }
    }

    /** "Meera Krishnan" -> "M*** K***": enough to recognise the account, not enough to disclose it. */
    static String maskName(String fullName) {
        if (fullName == null || fullName.isBlank()) {
            return "";
        }
        return java.util.Arrays.stream(fullName.trim().split("\\s+"))
                .map(word -> word.charAt(0) + "***")
                .collect(Collectors.joining(" "));
    }
}
