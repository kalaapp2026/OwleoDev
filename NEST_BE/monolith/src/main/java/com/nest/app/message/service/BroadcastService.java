package com.nest.app.message.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.event.entity.EventAudienceType;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.message.dto.AudiencePreviewRequest;
import com.nest.app.message.dto.BroadcastDetailResponse;
import com.nest.app.message.dto.BroadcastResponse;
import com.nest.app.message.dto.CreateBroadcastRequest;
import com.nest.app.message.entity.AcademyBroadcast;
import com.nest.app.message.repository.AcademyBroadcastRepository;
import com.nest.app.notification.entity.AppNotification;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The Messages module's broadcast side: an Academy Admin composes a message to a resolved
 * audience, fanned out through the existing notification bell rather than a new channel.
 *
 * <p>Composing is Admin-only - none of the 13 existing feature keys maps to "send a broadcast",
 * and inventing a new delegable one is a bigger follow-on (a new migration and trainer-grant UI).
 * Trainers still fully receive and read broadcasts like everyone else. The role check lives here
 * rather than behind {@code @RequiresFeature}, matching how other admin-only-not-feature-gated
 * actions in this codebase are enforced (see AttendanceService#assertEditable's identical role
 * check).
 *
 * <p>Audience targeting deliberately mirrors {@code EventService} - same five types, same
 * resolution path through {@link BatchRepository}/{@link BatchMemberRepository} - since a
 * broadcast's "who does this reach" question is identical to an event's.
 */
@Service
public class BroadcastService {

    private final AcademyBroadcastRepository broadcastRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final NotificationService notificationService;
    private final CourseRepository courseRepository;
    private final UserRepository userRepository;

    public BroadcastService(AcademyBroadcastRepository broadcastRepository, AcademyMembershipRepository membershipRepository,
                             BatchRepository batchRepository, BatchMemberRepository batchMemberRepository,
                             NotificationService notificationService, CourseRepository courseRepository,
                             UserRepository userRepository) {
        this.broadcastRepository = broadcastRepository;
        this.membershipRepository = membershipRepository;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.notificationService = notificationService;
        this.courseRepository = courseRepository;
        this.userRepository = userRepository;
    }

    @Transactional
    @Auditable(action = "ACADEMY_BROADCAST_SENT", entityType = "academy_broadcast")
    public BroadcastResponse create(CreateBroadcastRequest request) {
        MembershipClaim membership = assertAdmin();

        Set<UUID> courseIds = request.courseIds() == null ? Set.of() : request.courseIds();
        Set<UUID> batchIds = request.batchIds() == null ? Set.of() : request.batchIds();
        Set<UUID> individualIds = request.individualIds() == null ? Set.of() : request.individualIds();
        Set<UUID> recipientUserIds = resolveRecipientUsers(
                membership.academyId(), request.audienceType(), courseIds, batchIds, individualIds);
        String title = request.title() == null || request.title().isBlank() ? "Announcement" : request.title().trim();
        String body = request.body().trim();

        AcademyBroadcast broadcast = broadcastRepository.save(AcademyBroadcast.builder()
                .academyId(membership.academyId())
                .title(title)
                .body(body)
                .audienceType(request.audienceType())
                .courseIds(new HashSet<>(courseIds))
                .batchIds(new HashSet<>(batchIds))
                .individualIds(new HashSet<>(individualIds))
                .recipientCount(recipientUserIds.size())
                .createdBy(TenantContext.currentUserId())
                .build());

        // ERP-only, unlike the membership-confirmation OTP's dual-bell post: a broadcast's
        // recipients are by construction already-ACTIVE members of this academy, so the ERP bell
        // is always reachable - there's no "might have no membership yet" case to cover here.
        for (UUID userId : recipientUserIds) {
            notificationService.notifyBroadcast(userId, NotificationModule.ERP, NotificationType.ACADEMY_BROADCAST,
                    title, body, broadcast.getId());
        }

        return toResponse(broadcast, Map.of(), labelsFor(List.of(broadcast)));
    }

    /** How many people an audience would reach right now - the compose screen's live count. */
    @Transactional(readOnly = true)
    public int preview(AudiencePreviewRequest request) {
        MembershipClaim membership = assertAdmin();
        return resolveRecipientUsers(membership.academyId(), request.audienceType(),
                request.courseIds() == null ? Set.of() : request.courseIds(),
                request.batchIds() == null ? Set.of() : request.batchIds(),
                request.individualIds() == null ? Set.of() : request.individualIds()).size();
    }

    @Transactional(readOnly = true)
    public List<BroadcastResponse> list() {
        List<AcademyBroadcast> broadcasts =
                broadcastRepository.findByAcademyIdOrderByCreatedAtDesc(TenantContext.currentAcademyId());
        Map<UUID, Integer> reads = broadcasts.isEmpty()
                ? Map.of()
                : notificationService.readCountsForBroadcasts(broadcasts.stream().map(AcademyBroadcast::getId).toList());
        Map<UUID, String> labels = labelsFor(broadcasts);
        return broadcasts.stream().map(b -> toResponse(b, reads, labels)).collect(Collectors.toList());
    }

    /** One broadcast with each recipient and whether they have opened it. */
    @Transactional(readOnly = true)
    public BroadcastDetailResponse detail(UUID broadcastId) {
        assertAdmin();
        AcademyBroadcast broadcast = broadcastRepository.findById(broadcastId)
                .filter(b -> b.getAcademyId().equals(TenantContext.currentAcademyId()))
                .orElseThrow(() -> new ResourceNotFoundException("Broadcast not found: " + broadcastId));

        List<AppNotification> copies = notificationService.copiesOfBroadcast(broadcastId);
        // A broadcast sent before read tracking has no copies: report no read figure, not zero.
        Map<UUID, Integer> reads = copies.isEmpty() ? Map.of()
                : Map.of(broadcastId, (int) copies.stream().filter(n -> n.getReadAt() != null).count());

        Set<UUID> userIds = copies.stream().map(AppNotification::getUserId).collect(Collectors.toSet());
        Map<UUID, AcademyMembership> membershipByUser = new HashMap<>();
        for (AcademyMembership m : membershipRepository.findByAcademyId(broadcast.getAcademyId())) {
            if (userIds.contains(m.getUserId())) {
                membershipByUser.putIfAbsent(m.getUserId(), m);
            }
        }
        Map<UUID, User> users = userRepository.findAllById(userIds).stream()
                .collect(Collectors.toMap(User::getId, u -> u));

        List<BroadcastDetailResponse.Recipient> recipients = new ArrayList<>();
        for (AppNotification copy : copies) {
            AcademyMembership m = membershipByUser.get(copy.getUserId());
            User u = users.get(copy.getUserId());
            if (m == null || u == null) {
                continue;
            }
            String name = u.getFullName() != null && !u.getFullName().isBlank() ? u.getFullName() : u.getUsername();
            recipients.add(new BroadcastDetailResponse.Recipient(m.getId(), name, m.getRoleType(), copy.getReadAt() != null));
        }
        recipients.sort(Comparator.comparing((BroadcastDetailResponse.Recipient r) -> r.name().toLowerCase()));
        return new BroadcastDetailResponse(toResponse(broadcast, reads, labelsFor(List.of(broadcast))), recipients);
    }

    private MembershipClaim assertAdmin() {
        MembershipClaim membership = TenantContext.currentMembership();
        if (membership.roleType() != Role.ACADEMY_ADMIN) {
            throw new ForbiddenException("Only an Academy Admin can send a broadcast.");
        }
        return membership;
    }

    /**
     * The distinct USERS an audience reaches. Audience ids come from the request, so they are
     * re-checked here against this academy: an id from another academy, or a revoked member, is
     * dropped rather than notified. One person holding two memberships counts once.
     */
    private Set<UUID> resolveRecipientUsers(UUID academyId, EventAudienceType audienceType,
                                             Set<UUID> courseIds, Set<UUID> batchIds, Set<UUID> individualIds) {
        Set<UUID> membershipIds = resolveRecipients(academyId, audienceType, courseIds, batchIds, individualIds);
        if (membershipIds.isEmpty()) {
            return Set.of();
        }
        return membershipRepository.findAllById(membershipIds).stream()
                .filter(m -> academyId.equals(m.getAcademyId()) && m.getStatus() == MembershipStatus.ACTIVE)
                .map(AcademyMembership::getUserId).collect(Collectors.toSet());
    }

    private Set<UUID> resolveRecipients(UUID academyId, EventAudienceType audienceType,
                                         Set<UUID> courseIds, Set<UUID> batchIds, Set<UUID> individualIds) {
        return switch (audienceType) {
            case ALL_STUDENTS -> membershipRepository
                    .findByAcademyIdAndRoleTypeAndStatus(academyId, Role.STUDENT, MembershipStatus.ACTIVE).stream()
                    .map(AcademyMembership::getId).collect(Collectors.toSet());
            case ALL_TRAINERS -> membershipRepository
                    .findByAcademyIdAndRoleTypeAndStatus(academyId, Role.TRAINER, MembershipStatus.ACTIVE).stream()
                    .map(AcademyMembership::getId).collect(Collectors.toSet());
            case BY_COURSE -> {
                if (courseIds.isEmpty()) {
                    yield Set.of();
                }
                Set<UUID> resolvedBatchIds = batchRepository.findByCourseIdIn(courseIds).stream()
                        .map(Batch::getId).collect(Collectors.toSet());
                yield membersOfBatches(resolvedBatchIds);
            }
            case BY_BATCH -> membersOfBatches(batchIds);
            case INDIVIDUALS -> individualIds;
        };
    }

    private Set<UUID> membersOfBatches(Set<UUID> batchIds) {
        if (batchIds.isEmpty()) {
            return Set.of();
        }
        return batchMemberRepository.findByBatchIdIn(batchIds).stream()
                .map(BatchMember::getMembershipId).collect(Collectors.toSet());
    }

    /** Audience in words, for every broadcast at once - course and batch names are two queries. */
    private Map<UUID, String> labelsFor(List<AcademyBroadcast> broadcasts) {
        Set<UUID> courseIds = broadcasts.stream().flatMap(b -> b.getCourseIds().stream()).collect(Collectors.toSet());
        Set<UUID> batchIds = broadcasts.stream().flatMap(b -> b.getBatchIds().stream()).collect(Collectors.toSet());
        Map<UUID, String> courseNames = courseIds.isEmpty() ? Map.of()
                : courseRepository.findAllById(courseIds).stream().collect(Collectors.toMap(Course::getId, Course::getName));
        Map<UUID, String> batchNames = batchIds.isEmpty() ? Map.of()
                : batchRepository.findAllById(batchIds).stream().collect(Collectors.toMap(Batch::getId, Batch::getName));
        Map<UUID, String> labels = new LinkedHashMap<>();
        for (AcademyBroadcast b : broadcasts) {
            labels.put(b.getId(), switch (b.getAudienceType()) {
                case ALL_STUDENTS -> "All students";
                case ALL_TRAINERS -> "All trainers";
                case BY_COURSE -> joinNames(b.getCourseIds(), courseNames, "Courses");
                case BY_BATCH -> joinNames(b.getBatchIds(), batchNames, "Batches");
                case INDIVIDUALS -> b.getIndividualIds().size() + (b.getIndividualIds().size() == 1 ? " individual" : " individuals");
            });
        }
        return labels;
    }

    private static String joinNames(Set<UUID> ids, Map<UUID, String> names, String fallback) {
        String joined = ids.stream().map(names::get).filter(n -> n != null).sorted().collect(Collectors.joining(", "));
        return joined.isEmpty() ? fallback : joined;
    }

    private BroadcastResponse toResponse(AcademyBroadcast b, Map<UUID, Integer> reads, Map<UUID, String> labels) {
        return new BroadcastResponse(b.getId(), b.getAcademyId(), b.getTitle(), b.getBody(), b.getAudienceType(),
                Set.copyOf(b.getCourseIds()), Set.copyOf(b.getBatchIds()), Set.copyOf(b.getIndividualIds()),
                b.getRecipientCount(), b.getCreatedBy(), b.getCreatedAt(), reads.get(b.getId()), labels.get(b.getId()));
    }
}
