package com.nest.app.identity.repository;

import com.nest.app.identity.entity.FeatureGrant;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface FeatureGrantRepository extends JpaRepository<FeatureGrant, UUID> {
    List<FeatureGrant> findByMembershipId(UUID membershipId);

    void deleteByMembershipId(UUID membershipId);
}
