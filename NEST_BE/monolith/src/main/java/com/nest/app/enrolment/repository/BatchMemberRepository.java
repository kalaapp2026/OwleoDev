package com.nest.app.enrolment.repository;

import com.nest.app.enrolment.entity.BatchMember;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

public interface BatchMemberRepository extends JpaRepository<BatchMember, UUID> {
    List<BatchMember> findByBatchId(UUID batchId);

    /** Roster sizes for a whole list of batches in one query - the batch list shows a student
     * count per row, which would otherwise be one query per row. */
    List<BatchMember> findByBatchIdIn(Collection<UUID> batchIds);

    List<BatchMember> findByMembershipId(UUID membershipId);

    boolean existsByBatchIdAndMembershipId(UUID batchId, UUID membershipId);

    void deleteByBatchIdAndMembershipId(UUID batchId, UUID membershipId);
}
