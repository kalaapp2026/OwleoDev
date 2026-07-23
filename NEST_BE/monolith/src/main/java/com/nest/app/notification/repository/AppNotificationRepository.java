package com.nest.app.notification.repository;

import com.nest.app.notification.entity.AppNotification;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AppNotificationRepository extends JpaRepository<AppNotification, UUID> {
    List<AppNotification> findByUserIdOrderByCreatedAtDesc(UUID userId);
}
