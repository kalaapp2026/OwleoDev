package com.nest.app.identity.repository;

import com.nest.app.identity.entity.FeatureGrant;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface FeatureGrantRepository extends JpaRepository<FeatureGrant, UUID> {
    List<FeatureGrant> findByMembershipId(UUID membershipId);

    // Bulk delete, not derived load-then-remove - see CourseFeatureGrantRepository's
    // deleteByMembershipId for why (Hibernate flushes inserts before deletes, so a
    // delete-then-reinsert of an unchanged row in one transaction needs the delete to actually
    // hit the database immediately, not just get queued).
    @Modifying(clearAutomatically = true)
    @Query("delete from FeatureGrant g where g.membershipId = :membershipId")
    void deleteByMembershipId(@Param("membershipId") UUID membershipId);
}
