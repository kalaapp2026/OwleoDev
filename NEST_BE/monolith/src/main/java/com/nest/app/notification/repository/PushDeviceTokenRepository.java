package com.nest.app.notification.repository;

import com.nest.app.notification.entity.PushDeviceToken;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface PushDeviceTokenRepository extends JpaRepository<PushDeviceToken, UUID> {
    List<PushDeviceToken> findByUserId(UUID userId);

    Optional<PushDeviceToken> findByToken(String token);

    void deleteByToken(String token);
}
