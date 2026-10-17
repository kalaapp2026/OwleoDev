package com.nest.app.notification.repository;

import com.nest.app.notification.entity.NotificationDelivery;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface NotificationDeliveryRepository extends JpaRepository<NotificationDelivery, UUID> {
    List<NotificationDelivery> findAllByOrderByCreatedAtDesc(Pageable pageable);
}
