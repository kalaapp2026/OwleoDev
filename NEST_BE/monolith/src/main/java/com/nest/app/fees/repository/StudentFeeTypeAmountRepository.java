package com.nest.app.fees.repository;

import com.nest.app.fees.entity.StudentFeeTypeAmount;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface StudentFeeTypeAmountRepository extends JpaRepository<StudentFeeTypeAmount, UUID> {

    Optional<StudentFeeTypeAmount> findByMembershipIdAndFeeTypeId(UUID membershipId, UUID feeTypeId);

    /** Every override on one fee type - the roster needs them all at once. */
    List<StudentFeeTypeAmount> findByFeeTypeId(UUID feeTypeId);

    List<StudentFeeTypeAmount> findByMembershipId(UUID membershipId);

    List<StudentFeeTypeAmount> findByFeeTypeIdIn(Collection<UUID> feeTypeIds);
}
