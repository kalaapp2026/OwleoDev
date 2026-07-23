package com.nest.app.enrolment.repository;

import com.nest.app.enrolment.entity.BatchMember;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface BatchMemberRepository extends JpaRepository<BatchMember, UUID> {
    List<BatchMember> findByBatchId(UUID batchId);

    List<BatchMember> findByMembershipId(UUID membershipId);

    boolean existsByBatchIdAndMembershipId(UUID batchId, UUID membershipId);

    void deleteByBatchIdAndMembershipId(UUID batchId, UUID membershipId);
}
