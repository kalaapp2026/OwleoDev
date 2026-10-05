package com.nest.app.profile.repository;

import com.nest.app.profile.entity.UserPerformanceLog;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface UserPerformanceLogRepository extends JpaRepository<UserPerformanceLog, UUID> {
    List<UserPerformanceLog> findByUserIdOrderByLoggedOnDesc(UUID userId);

    Optional<UserPerformanceLog> findByIdAndUserId(UUID id, UUID userId);
}
