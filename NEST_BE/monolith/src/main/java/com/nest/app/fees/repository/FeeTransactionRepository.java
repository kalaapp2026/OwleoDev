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

    /** Fees collected per academy, for every academy at once (Super Admin academy list). Joins
     * through Course because a transaction records a course, not an academy. This is the
     * academy's OWN revenue from its students - not what the academy owes the platform, which is
     * a separate concern (billing). */
    @Query("""
            select c.academyId, coalesce(sum(f.amountPaid), 0)
            from FeeTransaction f, Course c
            where f.courseId = c.id
            group by c.academyId
            """)
    List<Object[]> sumCollectedByAcademyGrouped();
}
