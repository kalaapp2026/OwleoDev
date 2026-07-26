package com.nest.app.enrolment.service;

import com.nest.app.enrolment.dto.RegisterTrainerRequest;
import com.nest.app.enrolment.dto.TrainerResponse;
import com.nest.app.enrolment.dto.TrainerSummaryResponse;
import com.nest.app.enrolment.dto.TrainerDetailResponse;
import com.nest.app.enrolment.dto.UpdateTrainerRequest;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseFeatureGrant;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseFeatureGrantRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.app.identity.service.UserWithTempPassword;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * PRD 3.5. Cascading delegation: the checklist a caller can hand out is capped at exactly what
 * they themselves hold (Trainer creators) or at every delegable feature (Admin creators, who
 * aren't gated by feature_grants at all - PRD 2.2/2.3). COURSE_MANAGEMENT and ABOUT_US_EDIT are
 * never delegable to a Trainer, full stop.
 */
@Service
public class TrainerRegistrationService {

    private final IdentityRegistrationService identityRegistrationService;
    private final CourseMapRepository courseMapRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;
    private final CourseFeatureGrantRepository courseFeatureGrantRepository;

    public TrainerRegistrationService(IdentityRegistrationService identityRegistrationService, CourseMapRepository courseMapRepository,
                                       AcademyMembershipRepository membershipRepository, UserRepository userRepository,
                                       CourseFeatureGrantRepository courseFeatureGrantRepository) {
        this.identityRegistrationService = identityRegistrationService;
        this.courseMapRepository = courseMapRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.courseFeatureGrantRepository = courseFeatureGrantRepository;
    }

    /** Pre-fills the trainer edit form: profile + the current per-course feature checklist. */
    @Transactional(readOnly = true)
    public TrainerDetailResponse getTrainerDetail(UUID membershipId) {
        AcademyMembership membership = trainerInActiveAcademy(membershipId);
        User user = userRepository.findById(membership.getUserId())
                .orElseThrow(() -> new ResourceNotFoundException("No account for this membership"));
        return new TrainerDetailResponse(user.getId(), membership.getId(), user.getUsername(), user.getFullName(),
                user.getPhone(), user.getEmail(), user.getDob(), user.getAddress(), user.getCity(), user.getState(),
                user.getYearsOfExperience(), courseFeaturesOf(membershipId));
    }

    @Transactional
    @Auditable(action = "TRAINER_UPDATED", entityType = "user")
    public TrainerResponse updateTrainer(UUID membershipId, UpdateTrainerRequest request) {
        AcademyMembership membership = trainerInActiveAcademy(membershipId);
        assertGrantable(request.courseFeatures());

        identityRegistrationService.updateTrainerProfile(membership.getUserId(), request.fullName(), request.phone(),
                request.email(), request.dob(), request.address(), request.city(), request.state(), request.yearsOfExperience());

        Map<UUID, BigDecimal> courseMap = new HashMap<>();
        request.courseFeatures().keySet().forEach(id -> courseMap.put(id, null));
        identityRegistrationService.reconcileCourseMap(membershipId, courseMap);
        identityRegistrationService.replaceCourseFeatureGrants(membershipId, request.courseFeatures(), TenantContext.currentUserId());

        User user = userRepository.findById(membership.getUserId()).orElseThrow();
        return new TrainerResponse(user.getId(), membership.getId(), user.getUsername(), null, request.courseFeatures());
    }

    private AcademyMembership trainerInActiveAcademy(UUID membershipId) {
        AcademyMembership membership = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Trainer not found: " + membershipId));
        if (!membership.getAcademyId().equals(TenantContext.currentAcademyId()) || membership.getRoleType() != Role.TRAINER) {
            throw new ForbiddenException("That trainer does not belong to the active academy");
        }
        return membership;
    }

    private Map<UUID, Set<String>> courseFeaturesOf(UUID membershipId) {
        return courseFeatureGrantRepository.findByMembershipId(membershipId).stream()
                .collect(Collectors.groupingBy(CourseFeatureGrant::getCourseId,
                        Collectors.mapping(CourseFeatureGrant::getFeatureKey, Collectors.toSet())));
    }

    /** Batch creation's "default trainer" picker + the Users trainer roster - every ACTIVE Trainer
     * membership mapped to this course, with a real name attached instead of a UUID (mirrors
     * StudentRegistrationService.listStudentsForCourse). Academy Admins are NOT included: an Admin
     * is not a Trainer, so they never appear in a course's trainer list even if they run classes.
     * {@code includeInactive} false (picker) drops course-deactivated trainers; true (management)
     * keeps them, flagged. */
    @Transactional(readOnly = true)
    public List<TrainerSummaryResponse> listTrainersForCourse(UUID courseId, boolean includeInactive) {
        UUID academyId = TenantContext.currentAcademyId();

        Map<UUID, Boolean> activeByMembership = courseMapRepository.findByCourseId(courseId).stream()
                .collect(Collectors.toMap(CourseMap::getMembershipId, CourseMap::isActive));
        if (activeByMembership.isEmpty()) {
            return List.of();
        }

        List<AcademyMembership> mappedTrainers = membershipRepository.findAllById(activeByMembership.keySet()).stream()
                .filter(m -> m.getAcademyId().equals(academyId))
                .filter(m -> m.getRoleType() == Role.TRAINER)
                .filter(m -> m.getStatus() == MembershipStatus.ACTIVE)
                .filter(m -> includeInactive || activeByMembership.getOrDefault(m.getId(), true))
                .toList();

        Map<UUID, User> usersById = userRepository.findAllById(
                mappedTrainers.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        return mappedTrainers.stream()
                .map(m -> {
                    User u = usersById.get(m.getUserId());
                    return new TrainerSummaryResponse(m.getId(), u.getId(), u.getUsername(), u.getFullName(),
                            activeByMembership.getOrDefault(m.getId(), true));
                })
                .collect(Collectors.toList());
    }

    @Transactional
    @Auditable(action = "TRAINER_REGISTERED", entityType = "user")
    public TrainerResponse registerTrainer(RegisterTrainerRequest request) {
        MembershipClaim creator = TenantContext.currentMembership();
        assertGrantable(request.courseFeatures());

        UserWithTempPassword trainer = identityRegistrationService.createTrainerWithPassword(
                request.username(), request.fullName(), request.phone(), request.email(), request.dob(),
                request.address(), request.city(), request.state(), request.yearsOfExperience(), Role.TRAINER);

        var membership = identityRegistrationService.createMembership(
                trainer.user().getId(), creator.academyId(), creator.academyName(), Role.TRAINER,
                MembershipStatus.ACTIVE, TenantContext.currentUserId());

        // The trainer is mapped to every course in the request (keys); course-map rows have no fee.
        java.util.Map<UUID, BigDecimal> courseMap = new java.util.HashMap<>();
        request.courseFeatures().keySet().forEach(id -> courseMap.put(id, null));
        identityRegistrationService.replaceCourseMap(membership.getId(), courseMap);

        identityRegistrationService.replaceCourseFeatureGrants(membership.getId(), request.courseFeatures(), TenantContext.currentUserId());

        return new TrainerResponse(trainer.user().getId(), membership.getId(), trainer.user().getUsername(),
                trainer.temporaryPassword(), request.courseFeatures());
    }

    /** Cascading-delegation cap (PRD 3.5), applied across the flat set of features requested over
     * ALL courses: nothing NON_DELEGABLE, and nothing the creator doesn't themselves hold. */
    private void assertGrantable(Map<UUID, Set<String>> courseFeatures) {
        Set<String> grantable = grantableFeatureSet(TenantContext.currentMembership());
        Set<String> allRequested = courseFeatures.values().stream().flatMap(Set::stream).collect(Collectors.toSet());

        Set<String> requestedNonDelegable = allRequested.stream()
                .filter(FeatureKey.NON_DELEGABLE::contains).collect(Collectors.toSet());
        if (!requestedNonDelegable.isEmpty()) {
            throw new ForbiddenException("These features are Admin-only and never delegable to a Trainer: " + requestedNonDelegable);
        }

        Set<String> notHeldByCreator = new HashSet<>(allRequested);
        notHeldByCreator.removeAll(grantable);
        if (!notHeldByCreator.isEmpty()) {
            throw new ForbiddenException("Cannot grant features you do not yourself hold: " + notHeldByCreator);
        }
    }

    private Set<String> grantableFeatureSet(MembershipClaim creator) {
        if (creator.roleType() == Role.ACADEMY_ADMIN) {
            return FeatureKey.ALL_DELEGABLE;
        }
        return creator.features();
    }
}
