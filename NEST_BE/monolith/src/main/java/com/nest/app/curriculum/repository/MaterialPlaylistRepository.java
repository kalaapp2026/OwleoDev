package com.nest.app.curriculum.repository;

import com.nest.app.curriculum.entity.MaterialPlaylist;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface MaterialPlaylistRepository extends JpaRepository<MaterialPlaylist, UUID> {

    /** A trainer's own playlists, newest last so the list reads in the order they were built. */
    List<MaterialPlaylist> findByMembershipIdOrderByCreatedAtAsc(UUID membershipId);
}
