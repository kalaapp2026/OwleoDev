package com.nest.identity.repository;

import com.nest.identity.entity.AcademyMembership;
import com.nest.identity.entity.MembershipStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface AcademyMembershipRepository extends JpaRepository<AcademyMembership, UUID> {
    List<AcademyMembership> findByUserIdAndStatus(UUID userId, MembershipStatus status);

    List<AcademyMembership> findByUserId(UUID userId);

    Optional<AcademyMembership> findByUserIdAndAcademyId(UUID userId, UUID academyId);

    boolean existsByUserIdAndAcademyIdAndStatusNot(UUID userId, UUID academyId, MembershipStatus status);
}
