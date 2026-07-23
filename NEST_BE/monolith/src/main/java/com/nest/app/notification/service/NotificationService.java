package com.nest.app.notification.service;

import com.nest.app.notification.dto.NotificationResponse;
import com.nest.app.notification.entity.AppNotification;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.repository.AppNotificationRepository;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class NotificationService {

    private final AppNotificationRepository repository;

    public NotificationService(AppNotificationRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public void notify(UUID userId, NotificationType type, String title, String body, String actionCode) {
        repository.save(AppNotification.builder()
                .userId(userId)
                .type(type)
                .title(title)
                .body(body)
                .actionCode(actionCode)
                .build());
    }

    @Transactional(readOnly = true)
    public List<NotificationResponse> listForUser(UUID userId) {
        return repository.findByUserIdOrderByCreatedAtDesc(userId).stream().map(this::toResponse).collect(Collectors.toList());
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

    private NotificationResponse toResponse(AppNotification n) {
        return new NotificationResponse(n.getId(), n.getType(), n.getTitle(), n.getBody(), n.getActionCode(),
                n.getReadAt() != null, n.getCreatedAt());
    }
}
