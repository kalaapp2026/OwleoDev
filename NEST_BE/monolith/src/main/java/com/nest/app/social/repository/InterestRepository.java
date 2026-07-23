package com.nest.app.social.repository;

import com.nest.app.social.entity.Interest;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface InterestRepository extends JpaRepository<Interest, UUID> {
    List<Interest> findByUserId(UUID userId);

    boolean existsByUserIdAndEventId(UUID userId, UUID eventId);

    boolean existsByUserIdAndPostId(UUID userId, UUID postId);
}
