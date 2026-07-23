package com.nest.app.enrolment.service;

import com.nest.app.enrolment.dto.RegisterTrainerRequest;
import com.nest.app.enrolment.dto.TrainerResponse;
import com.nest.app.enrolment.dto.TrainerSummaryResponse;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.app.identity.service.UserWithTempPassword;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
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

    public TrainerRegistrationService(IdentityRegistrationService identityRegistrationService, CourseMapRepository courseMapRepository,
                                       AcademyMembershipRepository membershipRepository, UserRepository userRepository) {
        this.identityRegistrationService = identityRegistrationService;
        this.courseMapRepository = courseMapRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
    }

    /** Batch creation's "default trainer" picker source - every ACTIVE Trainer membership mapped
     * to this course, with a real name attached instead of a UUID (mirrors
     * StudentRegistrationService.listStudentsForCourse for the roster picker) - PLUS every ACTIVE
     * Academy Admin in the academy, since an Admin often personally teaches too. Admins are never
     * mapped to a course via CourseMap (they have blanket academy access, not per-course
     * enrolment), so they're pulled in unconditionally rather than filtered by course mapping the
     * way a Trainer is. */
    @Transactional(readOnly = true)
    public List<TrainerSummaryResponse> listTrainersForCourse(UUID courseId) {
        UUID academyId = TenantContext.currentAcademyId();

        Set<UUID> courseMappedIds = courseMapRepository.findByCourseId(courseId).stream()
                .map(CourseMap::getMembershipId).collect(Collectors.toSet());

        List<AcademyMembership> mappedTrainers = courseMappedIds.isEmpty() ? List.of() : membershipRepository.findAllById(courseMappedIds).stream()
                .filter(m -> m.getAcademyId().equals(academyId))
                .filter(m -> m.getRoleType() == Role.TRAINER)
                .filter(m -> m.getStatus() == MembershipStatus.ACTIVE)
                .toList();

        List<AcademyMembership> admins =
                membershipRepository.findByAcademyIdAndRoleTypeAndStatus(academyId, Role.ACADEMY_ADMIN, MembershipStatus.ACTIVE);

        Map<UUID, AcademyMembership> membershipsById = new java.util.LinkedHashMap<>();
        mappedTrainers.forEach(m -> membershipsById.put(m.getId(), m));
        admins.forEach(m -> membershipsById.putIfAbsent(m.getId(), m));

        Map<UUID, User> usersById = userRepository.findAllById(
                membershipsById.values().stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        return membershipsById.values().stream()
                .map(m -> {
                    User u = usersById.get(m.getUserId());
                    return new TrainerSummaryResponse(m.getId(), u.getId(), u.getUsername(), u.getFullName());
                })
                .collect(Collectors.toList());
    }

    @Transactional
    @Auditable(action = "TRAINER_REGISTERED", entityType = "user")
    public TrainerResponse registerTrainer(RegisterTrainerRequest request) {
        MembershipClaim creator = TenantContext.currentMembership();
        Set<String> grantable = grantableFeatureSet(creator);

        Set<String> requestedNonDelegable = request.features().stream()
                .filter(FeatureKey.NON_DELEGABLE::contains).collect(Collectors.toSet());
        if (!requestedNonDelegable.isEmpty()) {
            throw new ForbiddenException("These features are Admin-only and never delegable to a Trainer: " + requestedNonDelegable);
        }

        Set<String> notHeldByCreator = new HashSet<>(request.features());
        notHeldByCreator.removeAll(grantable);
        if (!notHeldByCreator.isEmpty()) {
            throw new ForbiddenException(
                    "Cannot grant features you do not yourself hold: " + notHeldByCreator);
        }

        UserWithTempPassword trainer = identityRegistrationService.createUserWithPassword(
                request.username(), request.fullName(), request.phone(), request.email(), Role.TRAINER);

        var membership = identityRegistrationService.createMembership(
                trainer.user().getId(), creator.academyId(), creator.academyName(), Role.TRAINER,
                MembershipStatus.ACTIVE, TenantContext.currentUserId());

        identityRegistrationService.replaceFeatureGrants(membership.getId(), request.features(), TenantContext.currentUserId());

        // Collectors.toMap rejects null values (its merge-based impl requires non-null) - Trainer
        // course-map rows have no fee concept, so build the map by hand instead.
        java.util.Map<UUID, BigDecimal> courseMap = new java.util.HashMap<>();
        request.courseIds().forEach(id -> courseMap.put(id, null));
        identityRegistrationService.replaceCourseMap(membership.getId(), courseMap);

        return new TrainerResponse(trainer.user().getId(), membership.getId(), trainer.user().getUsername(),
                trainer.temporaryPassword(), request.features(), request.courseIds());
    }

    private Set<String> grantableFeatureSet(MembershipClaim creator) {
        if (creator.roleType() == Role.ACADEMY_ADMIN) {
            return FeatureKey.ALL_DELEGABLE;
        }
        return creator.features();
    }
}
