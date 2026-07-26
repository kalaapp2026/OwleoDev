package com.nest.app.identity.service;

import com.nest.app.identity.dto.ArtistApplicationResponse;
import com.nest.app.identity.entity.ArtistApplication;
import com.nest.app.identity.entity.ArtistApplicationStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.ArtistApplicationRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

/** PRD 7.4 addendum: a Guest applies to become an Artist; Super Admin approves or rejects.
 * Approval flips {@link User#getRole()} straight to ARTIST - nothing else about the account
 * changes (they keep their existing username/password/posts, if any, since Guests can already
 * browse and mark interest even before this). */
@Service
public class ArtistApplicationService {

    private final ArtistApplicationRepository applicationRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;

    public ArtistApplicationService(ArtistApplicationRepository applicationRepository, UserRepository userRepository,
                                    NotificationService notificationService) {
        this.applicationRepository = applicationRepository;
        this.userRepository = userRepository;
        this.notificationService = notificationService;
    }

    @Transactional
    @Auditable(action = "ARTIST_APPLICATION_SUBMITTED", entityType = "artist_application")
    public ArtistApplicationResponse apply() {
        UUID userId = TenantContext.currentUserId();
        User user = userRepository.findById(userId).orElseThrow(() -> new ResourceNotFoundException("User not found"));

        if (user.getRole() == Role.ARTIST) {
            throw new BadRequestException("You're already an Artist");
        }
        applicationRepository.findFirstByUserIdAndStatusOrderByCreatedAtDesc(userId, ArtistApplicationStatus.PENDING)
                .ifPresent(existing -> {
                    throw new BadRequestException("You already have a pending application");
                });

        ArtistApplication application = applicationRepository.save(
                ArtistApplication.builder().userId(userId).status(ArtistApplicationStatus.PENDING).build());

        // Every Super Admin gets an ERP-bell heads-up - this is an admin action item, not a social one.
        userRepository.findByRole(Role.SUPER_ADMIN).forEach(admin ->
                notificationService.notify(admin.getId(), NotificationModule.ERP, NotificationType.ADMIN_BROADCAST,
                        "New Artist application", user.getFullName() + " (@" + user.getUsername() + ") wants to become an Artist.", null));

        return toResponse(application, user);
    }

    @Transactional(readOnly = true)
    public List<ArtistApplicationResponse> listPending() {
        return applicationRepository.findByStatusOrderByCreatedAtAsc(ArtistApplicationStatus.PENDING).stream()
                .map(a -> toResponse(a, userRepository.findById(a.getUserId()).orElse(null)))
                .collect(Collectors.toList());
    }

    @Transactional
    @Auditable(action = "ARTIST_APPLICATION_APPROVED", entityType = "artist_application")
    public ArtistApplicationResponse approve(UUID applicationId) {
        ArtistApplication application = pendingOrThrow(applicationId);
        User user = userRepository.findById(application.getUserId())
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        user.setRole(Role.ARTIST);
        userRepository.save(user);

        application.setStatus(ArtistApplicationStatus.APPROVED);
        application.setDecidedBy(TenantContext.currentUserId());
        application.setDecidedAt(Instant.now());
        applicationRepository.save(application);

        notificationService.notify(user.getId(), NotificationModule.SOCIAL, NotificationType.ADMIN_BROADCAST,
                "You're now an Artist!", "Your application was approved - you can post to the feed now.", null);

        return toResponse(application, user);
    }

    @Transactional
    @Auditable(action = "ARTIST_APPLICATION_REJECTED", entityType = "artist_application")
    public ArtistApplicationResponse reject(UUID applicationId) {
        ArtistApplication application = pendingOrThrow(applicationId);
        User user = userRepository.findById(application.getUserId())
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        application.setStatus(ArtistApplicationStatus.REJECTED);
        application.setDecidedBy(TenantContext.currentUserId());
        application.setDecidedAt(Instant.now());
        applicationRepository.save(application);

        notificationService.notify(user.getId(), NotificationModule.SOCIAL, NotificationType.ADMIN_BROADCAST,
                "Artist application update", "Your application wasn't approved this time. You can still view and enjoy posts as a Guest.", null);

        return toResponse(application, user);
    }

    private ArtistApplication pendingOrThrow(UUID applicationId) {
        ArtistApplication application = applicationRepository.findById(applicationId)
                .orElseThrow(() -> new ResourceNotFoundException("Application not found: " + applicationId));
        if (application.getStatus() != ArtistApplicationStatus.PENDING) {
            throw new BadRequestException("This application was already decided");
        }
        return application;
    }

    private ArtistApplicationResponse toResponse(ArtistApplication a, User user) {
        return new ArtistApplicationResponse(a.getId(), a.getUserId(),
                user != null ? user.getUsername() : null, user != null ? user.getFullName() : null,
                a.getStatus(), a.getCreatedAt());
    }
}
