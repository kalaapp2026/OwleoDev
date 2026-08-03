package com.nest.app.identity.service;

import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.OtpPurpose;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/**
 * The consent step behind PRD 7.4: when someone who ALREADY has a NEST account is added to another
 * academy, that person - not the academy adding them - has to approve it. Shared by student and
 * trainer registration so the two can't drift apart, which matters because the delivery rules here
 * were got wrong once already (see below).
 */
@Service
public class MembershipConfirmationService {

    private final OtpService otpService;
    private final NotificationService notificationService;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;
    private final IdentityRegistrationService identityRegistrationService;

    public MembershipConfirmationService(OtpService otpService, NotificationService notificationService,
                                         AcademyMembershipRepository membershipRepository,
                                         UserRepository userRepository,
                                         IdentityRegistrationService identityRegistrationService) {
        this.otpService = otpService;
        this.notificationService = notificationService;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.identityRegistrationService = identityRegistrationService;
    }

    /**
     * Issues the code and puts it where the person can actually find it.
     *
     * @param joiningAs what they're being added as ("a student", "a trainer") - the recipient may
     *                  have no idea this academy exists, so the message has to say who wants what.
     */
    @Transactional
    public void sendConfirmation(User person, UUID membershipId, String academyName, String joiningAs, String detail) {
        String code = otpService.requestOtp(person.getPhone(), OtpPurpose.MEMBERSHIP_CONFIRMATION, membershipId);
        String title = "Confirm your enrolment";
        String body = academyName + " wants to add you as " + joiningAs
                + (detail == null || detail.isBlank() ? "" : " for " + detail)
                + ". Share this code with them to confirm it's really you: " + code;

        // Posted to BOTH bells on purpose - the one place we break the "ERP and Social never mix"
        // rule. The recipient by definition has no active membership at this academy, so the ERP
        // side may be entirely unreachable for them and an ERP-only notice would be invisible in
        // exactly the case it exists for.
        notificationService.notify(person.getId(), NotificationModule.ERP, NotificationType.MEMBERSHIP_CONFIRMATION,
                title, body, code);
        notificationService.notify(person.getId(), NotificationModule.SOCIAL, NotificationType.MEMBERSHIP_CONFIRMATION,
                title, body, code);
    }

    /**
     * Verifies the code the person read back and activates the membership.
     *
     * <p>The code is checked against the membership it was issued FOR, so a code for one pending
     * request can't be replayed to activate a different one.
     */
    @Transactional
    public AcademyMembership confirm(UUID membershipId, String code) {
        AcademyMembership membership = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Membership not found: " + membershipId));
        User person = userRepository.findById(membership.getUserId())
                .orElseThrow(() -> new ResourceNotFoundException("No NEST account for this membership"));

        UUID confirmedFor = otpService.verifyOtp(person.getPhone(), code, OtpPurpose.MEMBERSHIP_CONFIRMATION);
        if (!confirmedFor.equals(membership.getId())) {
            throw new BadRequestException("This code does not match the pending request");
        }
        return identityRegistrationService.applyConfirmedCourseGrant(membership.getId());
    }
}
