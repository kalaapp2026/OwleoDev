package com.nest.app.curriculum.repository;

import com.nest.app.curriculum.entity.MaterialPlaybackSettings;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface MaterialPlaybackSettingsRepository
        extends JpaRepository<MaterialPlaybackSettings, MaterialPlaybackSettings.Key> {

    Optional<MaterialPlaybackSettings> findByMembershipIdAndMaterialId(UUID membershipId, UUID materialId);
}
