package com.nest.app.identity.repository;

import com.nest.app.identity.entity.ArtistApplication;
import com.nest.app.identity.entity.ArtistApplicationStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface ArtistApplicationRepository extends JpaRepository<ArtistApplication, UUID> {
    List<ArtistApplication> findByStatusOrderByCreatedAtAsc(ArtistApplicationStatus status);

    Optional<ArtistApplication> findFirstByUserIdAndStatusOrderByCreatedAtDesc(UUID userId, ArtistApplicationStatus status);
}
