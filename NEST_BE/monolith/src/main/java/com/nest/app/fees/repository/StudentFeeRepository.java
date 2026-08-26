package com.nest.app.fees.repository;

import com.nest.app.fees.entity.StudentFee;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface StudentFeeRepository extends JpaRepository<StudentFee, UUID> {

    List<StudentFee> findByMembershipIdAndAcademyIdOrderByCreatedAtDesc(UUID membershipId, UUID academyId);

    List<StudentFee> findByAcademyId(UUID academyId);

    /** Tenant-scoped by construction - see the class note on why this table gets its own
     * academy_id rather than reaching through membership. */
    Optional<StudentFee> findByIdAndAcademyId(UUID id, UUID academyId);
}
