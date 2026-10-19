package com.nest.app.academy.service;

import com.nest.app.academy.dto.AcademySettingsDtos.CreateRequest;
import com.nest.app.academy.dto.AcademySettingsDtos.PlanSummary;
import com.nest.app.academy.dto.AcademySettingsDtos.RequestResponse;
import com.nest.app.academy.dto.AcademySettingsDtos.ResolveRequest;
import com.nest.app.academy.dto.AcademySettingsDtos.SettingsResponse;
import com.nest.app.academy.dto.AcademySettingsDtos.SubscriptionResponse;
import com.nest.app.academy.entity.Academy;
import com.nest.app.academy.entity.AcademyRequest;
import com.nest.app.academy.entity.AcademyRequestStatus;
import com.nest.app.academy.entity.AcademyRequestType;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.academy.repository.AcademyRequestRepository;
import com.nest.app.billing.entity.BillingPlan;
import com.nest.app.billing.repository.BillingPlanRepository;
import com.nest.app.billing.service.BillingService;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * The Academy Settings screen's server side: the academy's own preferences, its plan and usage,
 * and the requests an Academy Admin raises with the platform team.
 *
 * <p>Everything here is for the Academy Admin of the ACTIVE academy and is checked here, in the
 * service, against that membership - there is no feature grant for settings, and no id in any
 * request body that could point at a different academy. The Super Admin side
 * ({@link #listAll}, {@link #resolve}) is separate and gated by role on the controller.
 */
@Service
public class AcademySettingsService {

    /** The app's own locales - an academy picks one of the languages the app is translated into. */
    static final Set<String> SUPPORTED_LANGUAGES =
            Set.of("en", "hi", "kn", "ta", "te", "mr", "ml", "gu", "bn", "pt", "es", "ar");

    private static final Pattern EMAIL = Pattern.compile("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$");

    private final AcademyRepository academyRepository;
    private final AcademyRequestRepository requestRepository;
    private final BillingPlanRepository planRepository;
    private final BillingService billingService;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;

    public AcademySettingsService(AcademyRepository academyRepository, AcademyRequestRepository requestRepository,
                                  BillingPlanRepository planRepository, BillingService billingService,
                                  AcademyMembershipRepository membershipRepository, UserRepository userRepository) {
        this.academyRepository = academyRepository;
        this.requestRepository = requestRepository;
        this.planRepository = planRepository;
        this.billingService = billingService;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
    }

    // ---- Preferences ----

    @Transactional(readOnly = true)
    public SettingsResponse settings() {
        Academy academy = myAcademy();
        return new SettingsResponse(academy.getId(), academy.getName(), academy.getOwnerName(), academy.getDefaultLanguage());
    }

    @Transactional
    @Auditable(action = "ACADEMY_LANGUAGE_CHANGED", entityType = "academy")
    public SettingsResponse updateDefaultLanguage(String language) {
        String tag = language == null ? "" : language.trim().toLowerCase();
        if (!SUPPORTED_LANGUAGES.contains(tag)) {
            throw new BadRequestException("Unsupported language: " + language);
        }
        Academy academy = myAcademy();
        academy.setDefaultLanguage(tag);
        academyRepository.save(academy);
        return new SettingsResponse(academy.getId(), academy.getName(), academy.getOwnerName(), academy.getDefaultLanguage());
    }

    // ---- Plan and usage ----

    @Transactional(readOnly = true)
    public SubscriptionResponse subscription() {
        Academy academy = myAcademy();
        PlanSummary current = planRepository.findById(academy.getPlan()).map(AcademySettingsService::summary)
                // An academy on a plan code that has no row (the legacy "STANDARD" default) still gets
                // a card - it just has no price or limits to show.
                .orElse(new PlanSummary(academy.getPlan(), academy.getPlan(), null, null, null));
        long students = membershipRepository.countByAcademyIdAndRoleTypeAndStatus(academy.getId(), Role.STUDENT, MembershipStatus.ACTIVE);
        long trainers = membershipRepository.countByAcademyIdAndRoleTypeAndStatus(academy.getId(), Role.TRAINER, MembershipStatus.ACTIVE);
        List<PlanSummary> plans = planRepository.findByActiveTrueOrderByMonthlyPriceAsc().stream()
                .map(AcademySettingsService::summary).toList();
        return new SubscriptionResponse(current, students, trainers, plans);
    }

    // ---- Requests to the platform team ----

    @Transactional
    @Auditable(action = "ACADEMY_REQUEST_RAISED", entityType = "academy_request")
    public RequestResponse submit(CreateRequest request) {
        Academy academy = myAcademy();
        AcademyRequestType type = request.type();

        String subject = trimToNull(request.subject());
        String details = trimToNull(request.details());
        String targetEmail = trimToNull(request.targetEmail());
        String targetPlan = trimToNull(request.targetPlan());

        switch (type) {
            case SUPPORT -> {
                if (subject == null || details == null) {
                    throw new BadRequestException("Add a subject and a message.");
                }
            }
            case OWNERSHIP_TRANSFER -> {
                if (targetEmail == null || !EMAIL.matcher(targetEmail).matches()) {
                    throw new BadRequestException("Enter the new owner's email address.");
                }
            }
            case PLAN_CHANGE -> {
                if (targetPlan == null) {
                    throw new BadRequestException("Pick a plan to move to.");
                }
                BillingPlan plan = planRepository.findById(targetPlan)
                        .filter(BillingPlan::isActive)
                        .orElseThrow(() -> new BadRequestException("Unknown plan: " + targetPlan));
                if (plan.getCode().equals(academy.getPlan())) {
                    throw new BadRequestException("The academy is already on the " + plan.getDisplayName() + " plan.");
                }
            }
            case CANCEL_SUBSCRIPTION, ACADEMY_CLOSURE -> {
                // Nothing to validate beyond being the admin; the type says what is wanted.
            }
        }
        // A second ask of the same kind while one is still open would only give the team two things
        // to answer. SUPPORT is exempt - several separate messages are normal.
        if (type != AcademyRequestType.SUPPORT
                && requestRepository.existsByAcademyIdAndTypeAndStatus(academy.getId(), type, AcademyRequestStatus.PENDING)) {
            throw new ConflictException("You already have a pending request of this kind.");
        }

        AcademyRequest saved = requestRepository.save(AcademyRequest.builder()
                .academyId(academy.getId())
                .requestedBy(TenantContext.currentUserId())
                .type(type)
                .subject(subject)
                .details(details)
                .targetEmail(type == AcademyRequestType.OWNERSHIP_TRANSFER ? targetEmail : null)
                .reason(type == AcademyRequestType.OWNERSHIP_TRANSFER ? trimToNull(request.reason()) : null)
                .targetPlan(type == AcademyRequestType.PLAN_CHANGE ? targetPlan : null)
                .build());
        return toResponse(saved, Map.of(academy.getId(), academy.getName()), namesOf(Set.of(saved.getRequestedBy())));
    }

    /** The active academy's own requests, newest first. */
    @Transactional(readOnly = true)
    public List<RequestResponse> mine() {
        Academy academy = myAcademy();
        List<AcademyRequest> requests = requestRepository.findByAcademyIdOrderByCreatedAtDesc(academy.getId());
        Map<UUID, String> users = namesOf(requests.stream().map(AcademyRequest::getRequestedBy).collect(Collectors.toSet()));
        return requests.stream().map(r -> toResponse(r, Map.of(academy.getId(), academy.getName()), users)).toList();
    }

    // ---- Super Admin ----

    /** Every academy's requests, optionally just one status. Role-gated on the controller. */
    @Transactional(readOnly = true)
    public List<RequestResponse> listAll(AcademyRequestStatus status) {
        List<AcademyRequest> requests = status == null
                ? requestRepository.findAllByOrderByCreatedAtDesc()
                : requestRepository.findByStatusOrderByCreatedAtDesc(status);
        Map<UUID, String> academies = academyRepository.findAllById(
                requests.stream().map(AcademyRequest::getAcademyId).collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(Academy::getId, Academy::getName));
        Map<UUID, String> users = namesOf(requests.stream().map(AcademyRequest::getRequestedBy).collect(Collectors.toSet()));
        return requests.stream().map(r -> toResponse(r, academies, users)).toList();
    }

    /** Approving a plan change applies the plan; every other approval only records the decision,
     * because the rest (an ownership handover, a closure) is a deliberate step the team takes. */
    @Transactional
    @Auditable(action = "ACADEMY_REQUEST_RESOLVED", entityType = "academy_request")
    public RequestResponse resolve(UUID requestId, ResolveRequest resolution) {
        AcademyRequest request = requestRepository.findById(requestId)
                .orElseThrow(() -> new ResourceNotFoundException("Request not found: " + requestId));
        if (request.getStatus() != AcademyRequestStatus.PENDING) {
            throw new ConflictException("This request has already been answered.");
        }
        boolean approve = Boolean.TRUE.equals(resolution.approve());
        if (approve && request.getType() == AcademyRequestType.PLAN_CHANGE) {
            billingService.changePlan(request.getAcademyId(), request.getTargetPlan());
        }
        request.setStatus(approve ? AcademyRequestStatus.APPROVED : AcademyRequestStatus.DECLINED);
        request.setResolutionNote(trimToNull(resolution.note()));
        request.setResolvedBy(TenantContext.currentUserId());
        request.setResolvedAt(Instant.now());
        AcademyRequest saved = requestRepository.save(request);
        Map<UUID, String> academies = academyRepository.findById(saved.getAcademyId())
                .map(a -> Map.of(a.getId(), a.getName())).orElse(Map.of());
        return toResponse(saved, academies, namesOf(Set.of(saved.getRequestedBy())));
    }

    // ---- helpers ----

    private Academy myAcademy() {
        MembershipClaim membership = TenantContext.currentMembership();
        if (membership.roleType() != Role.ACADEMY_ADMIN) {
            throw new ForbiddenException("Only the Academy Admin can manage academy settings.");
        }
        UUID academyId = membership.academyId();
        return academyRepository.findById(academyId)
                .orElseThrow(() -> new ResourceNotFoundException("Academy not found: " + academyId));
    }

    private Map<UUID, String> namesOf(Set<UUID> userIds) {
        return userRepository.findAllById(userIds).stream().collect(Collectors.toMap(User::getId,
                u -> u.getFullName() != null && !u.getFullName().isBlank() ? u.getFullName() : u.getUsername()));
    }

    private static PlanSummary summary(BillingPlan p) {
        return new PlanSummary(p.getCode(), p.getDisplayName(), p.getMonthlyPrice(), p.getMaxStudents(), p.getMaxTrainers());
    }

    private static String trimToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static RequestResponse toResponse(AcademyRequest r, Map<UUID, String> academies, Map<UUID, String> users) {
        return new RequestResponse(r.getId(), r.getAcademyId(), academies.get(r.getAcademyId()), users.get(r.getRequestedBy()),
                r.getType(), r.getStatus(), r.getSubject(), r.getDetails(), r.getTargetEmail(), r.getReason(),
                r.getTargetPlan(), r.getResolutionNote(), r.getCreatedAt(), r.getResolvedAt());
    }
}
