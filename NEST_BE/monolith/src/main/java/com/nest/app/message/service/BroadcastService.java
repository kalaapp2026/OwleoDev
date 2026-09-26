package com.nest.app.message.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.event.entity.EventAudienceType;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.message.dto.BroadcastResponse;
import com.nest.app.message.dto.CreateBroadcastRequest;
import com.nest.app.message.entity.AcademyBroadcast;
import com.nest.app.message.repository.AcademyBroadcastRepository;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The Messages module's real-data MVP: an Academy Admin composes a broadcast to a resolved
 * audience, fanned out through the existing notification bell rather than a new channel.
 *
 * <p>Composing is Admin-only in this pass - none of the 13 existing feature keys maps to "send a
 * broadcast", and inventing a new delegable one is a bigger follow-on than this MVP (a new
 * migration and trainer-grant UI). Trainers still fully receive and read broadcasts like everyone
 * else. The role check lives here rather than behind {@code @RequiresFeature}, matching how other
 * admin-only-not-feature-gated actions in this codebase are enforced (see
 * AttendanceService#assertEditable's identical role check).
 *
 * <p>Audience targeting deliberately mirrors {@code EventService} exactly - same five types,
 * same resolution path through {@link BatchRepository}/{@link BatchMemberRepository} - since a
 * broadcast's "who does this reach" question is identical to an event's.
 */
@Service
public class BroadcastService {

    private final AcademyBroadcastRepository broadcastRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final NotificationService notificationService;

    public BroadcastService(AcademyBroadcastRepository broadcastRepository, AcademyMembershipRepository membershipRepository,
                             BatchRepository batchRepository, BatchMemberRepository batchMemberRepository,
                             NotificationService notificationService) {
        this.broadcastRepository = broadcastRepository;
        this.membershipRepository = membershipRepository;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.notificationService = notificationService;
    }

    @Transactional
    @Auditable(action = "ACADEMY_BROADCAST_SENT", entityType = "academy_broadcast")
    public BroadcastResponse create(CreateBroadcastRequest request) {
        MembershipClaim membership = TenantContext.currentMembership();
        if (membership.roleType() != Role.ACADEMY_ADMIN) {
            throw new ForbiddenException("Only an Academy Admin can send a broadcast.");
        }

        Set<UUID> courseIds = request.courseIds() == null ? Set.of() : request.courseIds();
        Set<UUID> batchIds = request.batchIds() == null ? Set.of() : request.batchIds();
        Set<UUID> individualIds = request.individualIds() == null ? Set.of() : request.individualIds();
        Set<UUID> recipientMembershipIds = resolveRecipients(
                membership.academyId(), request.audienceType(), courseIds, batchIds, individualIds);

        AcademyBroadcast broadcast = broadcastRepository.save(AcademyBroadcast.builder()
                .academyId(membership.academyId())
                .title(request.title())
                .body(request.body())
                .audienceType(request.audienceType())
                .courseIds(new HashSet<>(courseIds))
                .batchIds(new HashSet<>(batchIds))
                .individualIds(new HashSet<>(individualIds))
                .recipientCount(recipientMembershipIds.size())
                .createdBy(TenantContext.currentUserId())
                .build());

        // ERP-only, unlike the membership-confirmation OTP's dual-bell post: a broadcast's
        // recipients are by construction already-ACTIVE members of this academy, so the ERP bell
        // is always reachable - there's no "might have no membership yet" case to cover here.
        Set<UUID> recipientUserIds = membershipRepository.findAllById(recipientMembershipIds).stream()
                .map(AcademyMembership::getUserId).collect(Collectors.toSet());
        for (UUID userId : recipientUserIds) {
            notificationService.notify(userId, NotificationModule.ERP, NotificationType.ACADEMY_BROADCAST,
                    request.title(), request.body(), null);
        }

        return toResponse(broadcast);
    }

    @Transactional(readOnly = true)
    public List<BroadcastResponse> list() {
        return broadcastRepository.findByAcademyIdOrderByCreatedAtDesc(TenantContext.currentAcademyId()).stream()
                .map(this::toResponse).collect(Collectors.toList());
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

    private BroadcastResponse toResponse(AcademyBroadcast b) {
        return new BroadcastResponse(b.getId(), b.getAcademyId(), b.getTitle(), b.getBody(), b.getAudienceType(),
                Set.copyOf(b.getCourseIds()), Set.copyOf(b.getBatchIds()), Set.copyOf(b.getIndividualIds()),
                b.getRecipientCount(), b.getCreatedBy(), b.getCreatedAt());
    }
}
