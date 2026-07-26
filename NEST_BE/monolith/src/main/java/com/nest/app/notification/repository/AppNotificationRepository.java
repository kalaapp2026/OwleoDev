package com.nest.app.notification.repository;

import com.nest.app.notification.entity.AppNotification;
import com.nest.app.notification.entity.NotificationModule;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AppNotificationRepository extends JpaRepository<AppNotification, UUID> {
    List<AppNotification> findByUserIdAndModuleOrderByCreatedAtDesc(UUID userId, NotificationModule module);

    long countByUserIdAndModuleAndReadAtIsNull(UUID userId, NotificationModule module);
}
