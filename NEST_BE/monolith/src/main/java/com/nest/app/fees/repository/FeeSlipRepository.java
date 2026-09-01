package com.nest.app.fees.repository;

import com.nest.app.fees.entity.FeeSlip;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface FeeSlipRepository extends JpaRepository<FeeSlip, UUID> {
    Optional<FeeSlip> findByMembershipIdAndCourseIdAndPeriod(UUID membershipId, UUID courseId, String period);

    List<FeeSlip> findByMembershipIdOrderByGeneratedAtDesc(UUID membershipId);

    List<FeeSlip> findByCourseIdAndPeriod(UUID courseId, String period);

    /** Slips for a whole academy in one period, for the dashboard aggregate. */
    List<FeeSlip> findByCourseIdInAndPeriod(List<UUID> courseIds, String period);

    /** The immediately preceding period's slip for this membership+course, if any - "period" is
     * "YYYY-MM" so lexicographic ordering is also chronological ordering. Drives carry-forward:
     * an unpaid OPEN prior slip's remainder rolls into the next one generated. */
    Optional<FeeSlip> findFirstByMembershipIdAndCourseIdAndPeriodLessThanOrderByPeriodDesc(
            UUID membershipId, UUID courseId, String period);
}
