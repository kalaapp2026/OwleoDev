package com.nest.app.profile.repository;

import com.nest.app.profile.entity.UserAchievement;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface UserAchievementRepository extends JpaRepository<UserAchievement, UUID> {
    List<UserAchievement> findByUserIdOrderByAchievedOnDesc(UUID userId);

    /** Always scoped by owner - the id alone must never reach another person's row. */
    Optional<UserAchievement> findByIdAndUserId(UUID id, UUID userId);
}
