package com.nest.app.notification.service;

import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.notification.dto.BroadcastRequest;
import com.nest.app.notification.dto.NotificationResponse;
import com.nest.app.notification.entity.AppNotification;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.repository.AppNotificationRepository;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class NotificationService {

    private final AppNotificationRepository repository;
    private final UserRepository userRepository;
    private final AcademyMembershipRepository membershipRepository;

    public NotificationService(AppNotificationRepository repository, UserRepository userRepository,
                               AcademyMembershipRepository membershipRepository) {
        this.repository = repository;
        this.userRepository = userRepository;
        this.membershipRepository = membershipRepository;
    }

    /** The single write path every trigger (automated or the Super Admin console) funnels through -
     * {@code module} is what keeps ERP and Social notifications from bleeding into each other's bell. */
    @Transactional
    public void notify(UUID userId, NotificationModule module, NotificationType type, String title, String body, String actionCode) {
        repository.save(AppNotification.builder()
                .userId(userId)
                .module(module)
                .type(type)
                .title(title)
                .body(body)
                .actionCode(actionCode)
                .build());
    }

    @Transactional(readOnly = true)
    public List<NotificationResponse> listForUser(UUID userId, NotificationModule module) {
        return repository.findByUserIdAndModuleOrderByCreatedAtDesc(userId, module).stream()
                .map(this::toResponse).collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public long unreadCount(UUID userId, NotificationModule module) {
        return repository.countByUserIdAndModuleAndReadAtIsNull(userId, module);
    }

    @Transactional
    public void markRead(UUID notificationId, UUID userId) {
        AppNotification notification = repository.findById(notificationId)
                .orElseThrow(() -> new ResourceNotFoundException("Notification not found: " + notificationId));
        if (!notification.getUserId().equals(userId)) {
            throw new ResourceNotFoundException("Notification not found: " + notificationId);
        }
        if (notification.getReadAt() == null) {
            notification.setReadAt(Instant.now());
            repository.save(notification);
        }
    }

    /** Super Admin console (PRD 2.x): fan a single composed announcement out to one row per target
     * user. Returns how many recipients it reached, so the console can confirm "sent to N people". */
    @Transactional
    public int broadcast(BroadcastRequest request) {
        Set<UUID> recipientUserIds = resolveAudience(request);
        recipientUserIds.forEach(userId -> notify(userId, request.module(), NotificationType.ADMIN_BROADCAST,
                request.title(), request.body(), null));
        return recipientUserIds.size();
    }

    // Deliberately an if/else, not a switch expression on BroadcastAudience: an enum switch here
    // triggers a reproducible javac/Maven incremental-compile defect on this toolchain (the
    // generated $1 switch-map inner class goes missing from target/classes on `spring-boot:run`'s
    // own recompile step, throwing NoClassDefFoundError at call time even right after a clean
    // build - see incident notes). If/else has no synthetic class to go stale.
    private Set<UUID> resolveAudience(BroadcastRequest request) {
        if (request.audience() == BroadcastRequest.BroadcastAudience.EVERYONE) {
            return userRepository.findAll().stream().map(User::getId).collect(Collectors.toSet());
        }
        if (request.academyId() == null) {
            throw new BadRequestException("academyId is required when targeting a single academy");
        }
        return membershipRepository.findByAcademyId(request.academyId()).stream()
                .map(AcademyMembership::getUserId).collect(Collectors.toSet());
    }

    private NotificationResponse toResponse(AppNotification n) {
        return new NotificationResponse(n.getId(), n.getModule(), n.getType(), n.getTitle(), n.getBody(),
                n.getActionCode(), n.getReadAt() != null, n.getCreatedAt());
    }
}
