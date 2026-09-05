package com.nest.app.enrolment.service;

import com.nest.app.enrolment.dto.RegisterTrainerRequest;
import com.nest.app.enrolment.dto.TrainerResponse;
import com.nest.app.enrolment.dto.TrainerSummaryResponse;
import com.nest.app.enrolment.dto.TrainerDetailResponse;
import com.nest.app.enrolment.dto.UpdateTrainerRequest;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
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
import com.nest.app.identity.service.MembershipConfirmationService;
import com.nest.app.identity.service.UserWithTempPassword;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
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
import java.util.Optional;
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
    private final CourseRepository courseRepository;
    private final MembershipConfirmationService membershipConfirmationService;
    private final com.nest.app.identity.repository.TrainerCourseBatchRepository trainerCourseBatchRepository;

    public TrainerRegistrationService(IdentityRegistrationService identityRegistrationService, CourseMapRepository courseMapRepository,
                                       AcademyMembershipRepository membershipRepository, UserRepository userRepository,
                                       CourseFeatureGrantRepository courseFeatureGrantRepository,
                                       CourseRepository courseRepository,
                                       MembershipConfirmationService membershipConfirmationService,
                                       com.nest.app.identity.repository.TrainerCourseBatchRepository trainerCourseBatchRepository) {
        this.identityRegistrationService = identityRegistrationService;
        this.courseMapRepository = courseMapRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.courseFeatureGrantRepository = courseFeatureGrantRepository;
        this.courseRepository = courseRepository;
        this.membershipConfirmationService = membershipConfirmationService;
        this.trainerCourseBatchRepository = trainerCourseBatchRepository;
    }

    /** Pre-fills the trainer edit form: profile + the current per-course feature checklist. */
    @Transactional(readOnly = true)
    public TrainerDetailResponse getTrainerDetail(UUID membershipId) {
        AcademyMembership membership = trainerInActiveAcademy(membershipId);
        User user = userRepository.findById(membership.getUserId())
                .orElseThrow(() -> new ResourceNotFoundException("No account for this membership"));
        return new TrainerDetailResponse(user.getId(), membership.getId(), user.getUsername(), user.getFullName(),
                user.getPhone(), user.getEmail(), user.getDob(), user.getAddress(), user.getCity(), user.getState(),
                user.getYearsOfExperience(), courseFeaturesOf(membershipId),
                identityRegistrationService.personDetailsOf(user, membership),
                courseBatchesOf(membershipId));
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
        saveBatchScoping(membershipId, request.courseBatches());

        User user = userRepository.findById(membership.getUserId()).orElseThrow();
        identityRegistrationService.applyPersonDetails(user, request.details());
        if (request.details() != null) {
            identityRegistrationService.setJoiningDate(membership, request.details().joiningDate());
            identityRegistrationService.setSalary(membership, request.details().salary());
        }
        return new TrainerResponse(user.getId(), membership.getId(), user.getUsername(), null,
                request.courseFeatures(), false);
    }

    private AcademyMembership trainerInActiveAcademy(UUID membershipId) {
        AcademyMembership membership = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Trainer not found: " + membershipId));
        if (!membership.getAcademyId().equals(TenantContext.currentAcademyId()) || membership.getRoleType() != Role.TRAINER) {
            throw new ForbiddenException("That trainer does not belong to the active academy");
        }
        return membership;
    }

    /** courseId -&gt; the batches this trainer is scoped to on it. A course with no rows is absent
     * from the map, which reads as "every batch on that course". */
    private Map<UUID, Set<UUID>> courseBatchesOf(UUID membershipId) {
        return trainerCourseBatchRepository.findByMembershipId(membershipId).stream()
                .collect(Collectors.groupingBy(
                        com.nest.app.identity.entity.TrainerCourseBatch::getCourseId,
                        Collectors.mapping(com.nest.app.identity.entity.TrainerCourseBatch::getBatchId,
                                Collectors.toSet())));
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

        // Someone already on NEST - a student at another academy, or a trainer teaching elsewhere -
        // must NOT get a second account. Their email is their identity across the whole platform
        // (PRD 7.4), so we link them to this academy instead of rejecting them as a duplicate.
        Optional<User> existing = identityRegistrationService.findByEmail(request.email());
        if (existing.isPresent()) {
            return linkExistingPerson(existing.get(), creator, request);
        }

        UserWithTempPassword trainer = identityRegistrationService.createTrainerWithPassword(
                request.username(), request.fullName(), request.phone(), request.email(), request.dob(),
                request.address(), request.city(), request.state(), request.yearsOfExperience(), Role.TRAINER);

        identityRegistrationService.applyPersonDetails(trainer.user(), request.details());

        var membership = identityRegistrationService.createMembership(
                trainer.user().getId(), creator.academyId(), creator.academyName(), Role.TRAINER,
                MembershipStatus.ACTIVE, TenantContext.currentUserId());
        identityRegistrationService.setJoiningDate(membership,
                request.details() == null ? null : request.details().joiningDate());
        identityRegistrationService.setSalary(membership,
                request.details() == null ? null : request.details().salary());

        saveCourseAssignment(membership.getId(), request.courseFeatures());
        saveBatchScoping(membership.getId(), request.courseBatches());

        return new TrainerResponse(trainer.user().getId(), membership.getId(), trainer.user().getUsername(),
                trainer.temporaryPassword(), request.courseFeatures(), false);
    }

    /**
     * Links an existing NEST account to this academy as a Trainer, pending that person's own
     * approval. Their global role and password are untouched - someone can be a Student at one
     * academy and a Trainer at another, because what they can do is decided by the per-academy
     * membership, not by the account.
     *
     * <p>The course map and feature grants are written straight away even though the membership
     * isn't active yet: PrincipalAssembler only ever reads ACTIVE memberships, so those rows grant
     * nothing until confirmation flips the status. That's simpler than staging them somewhere
     * else and having to replay it later.
     */
    private TrainerResponse linkExistingPerson(User person, MembershipClaim creator, RegisterTrainerRequest request) {
        identityRegistrationService.findMembership(person.getId(), creator.academyId()).ifPresent(existing -> {
            // One membership per person per academy - so this is "already here", not "add another".
            throw new BadRequestException(person.getFullName() + " is already "
                    + article(existing.getRoleType()) + " at this academy"
                    + (existing.getStatus() == MembershipStatus.PENDING_CONFIRMATION
                            ? ", with a request still awaiting their confirmation." : "."));
        });

        var membership = identityRegistrationService.createMembership(
                person.getId(), creator.academyId(), creator.academyName(), Role.TRAINER,
                MembershipStatus.PENDING_CONFIRMATION, TenantContext.currentUserId());
        identityRegistrationService.setJoiningDate(membership,
                request.details() == null ? null : request.details().joiningDate());
        identityRegistrationService.setSalary(membership,
                request.details() == null ? null : request.details().salary());

        saveCourseAssignment(membership.getId(), request.courseFeatures());
        saveBatchScoping(membership.getId(), request.courseBatches());

        String courseNames = courseRepository.findAllById(request.courseFeatures().keySet()).stream()
                .map(Course::getName).collect(Collectors.joining(", "));
        membershipConfirmationService.sendConfirmation(
                person, membership.getId(), creator.academyName(), "a trainer", courseNames);

        // No temp password: they already have an account and keep their existing credentials.
        return new TrainerResponse(person.getId(), membership.getId(), person.getUsername(),
                null, request.courseFeatures(), true);
    }

    /** Completes the link once the person reads their code back to whoever registered them. */
    @Transactional
    @Auditable(action = "TRAINER_MEMBERSHIP_CONFIRMED", entityType = "academy_membership")
    public TrainerResponse confirmMembership(UUID membershipId, String code) {
        AcademyMembership confirmed = membershipConfirmationService.confirm(membershipId, code);
        User person = userRepository.findById(confirmed.getUserId())
                .orElseThrow(() -> new ResourceNotFoundException("No account for this membership"));
        return new TrainerResponse(person.getId(), confirmed.getId(), person.getUsername(),
                null, courseFeaturesOf(confirmed.getId()), false);
    }

    /** A trainer's course rows carry no fee - they're a mapping, not an enrolment. */
    /**
     * Records which batches a trainer's course grants apply to.
     *
     * <p>A course with no batches listed writes no rows, which reads as "every batch on that
     * course" - the access a trainer had before batches could be named individually, and the
     * right default for the common case where they teach all of them.
     */
    private void saveBatchScoping(UUID membershipId, Map<UUID, Set<UUID>> courseBatches) {
        // Null means "not specified", which on an edit must leave the existing scoping alone.
        // Deleting first and then returning would silently widen a batch-scoped trainer to the
        // whole course, since an absent row set is read as "every batch".
        if (courseBatches == null) {
            return;
        }
        trainerCourseBatchRepository.deleteByMembershipId(membershipId);
        courseBatches.forEach((courseId, batchIds) -> {
            if (batchIds == null) {
                return;
            }
            batchIds.forEach(batchId -> trainerCourseBatchRepository.save(
                    com.nest.app.identity.entity.TrainerCourseBatch.builder()
                            .membershipId(membershipId).courseId(courseId).batchId(batchId).build()));
        });
    }

    private void saveCourseAssignment(UUID membershipId, Map<UUID, Set<String>> courseFeatures) {
        Map<UUID, BigDecimal> courseMap = new HashMap<>();
        courseFeatures.keySet().forEach(id -> courseMap.put(id, null));
        identityRegistrationService.replaceCourseMap(membershipId, courseMap);
        identityRegistrationService.replaceCourseFeatureGrants(membershipId, courseFeatures, TenantContext.currentUserId());
    }

    private String article(Role role) {
        String name = role.name().replace('_', ' ').toLowerCase();
        return (name.startsWith("a") ? "an " : "a ") + name;
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
