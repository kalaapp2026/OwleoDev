package com.nest.app.fees.repository;

import com.nest.app.fees.entity.FeeTransaction;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

public interface FeeTransactionRepository extends JpaRepository<FeeTransaction, UUID> {

    List<FeeTransaction> findByMembershipIdOrderByCreatedAtDesc(UUID membershipId);

    List<FeeTransaction> findByMembershipIdAndCourseIdAndPeriod(UUID membershipId, UUID courseId, String period);

    @Query("select coalesce(sum(f.amountPaid), 0) from FeeTransaction f " +
            "where f.membershipId = :membershipId and f.courseId = :courseId and f.period = :period")
    BigDecimal sumPaid(@Param("membershipId") UUID membershipId, @Param("courseId") UUID courseId, @Param("period") String period);

    List<FeeTransaction> findByCourseIdAndPeriod(UUID courseId, String period);
}
