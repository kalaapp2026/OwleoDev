package com.nest.app.selfservice.repository;

import com.nest.app.selfservice.entity.AccountDeletionRequest;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface AccountDeletionRequestRepository extends JpaRepository<AccountDeletionRequest, UUID> {
    Optional<AccountDeletionRequest> findFirstByMembershipIdAndStatus(UUID membershipId, String status);
}
