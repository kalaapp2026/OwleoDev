package com.nest.app.fees.repository;

import com.nest.app.fees.entity.FeeTransaction;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface FeeTransactionRepository extends JpaRepository<FeeTransaction, UUID> {

    List<FeeTransaction> findByMembershipIdOrderByCreatedAtDesc(UUID membershipId);

    List<FeeTransaction> findByMembershipIdAndCourseIdAndPeriod(UUID membershipId, UUID courseId, String period);

    @Query("select coalesce(sum(f.amountPaid), 0) from FeeTransaction f " +
            "where f.membershipId = :membershipId and f.courseId = :courseId and f.period = :period")
    BigDecimal sumPaid(@Param("membershipId") UUID membershipId, @Param("courseId") UUID courseId, @Param("period") String period);

    List<FeeTransaction> findByCourseIdAndPeriod(UUID courseId, String period);

    /** Fees collected per academy, for every academy at once (Super Admin academy list). This is
     * the academy's OWN revenue from its students - not what the academy owes the platform, which
     * is a separate concern (billing).
     *
     * <p>Groups on the transaction's own academyId rather than joining through Course. The join
     * predated Other Fees and would now quietly drop every one of them from the total, since an
     * Other row has no course to join on.</p> */
    @Query("""
            select f.academyId, coalesce(sum(f.amountPaid), 0)
            from FeeTransaction f
            group by f.academyId
            """)
    List<Object[]> sumCollectedByAcademyGrouped();

    /** Every course's transactions for one student in one period, so the profile screen builds its
     * whole breakdown from a single query rather than one per enrolment. */
    List<FeeTransaction> findByMembershipIdAndPeriod(UUID membershipId, String period);

    // ---- ledger ----

    /**
     * The balance owed on one Other fee is the fee's amount less this sum. Never stored: a
     * reversal is a negative row, so the same SUM answers "what is owed now" both before and
     * after an undo with no extra state to keep in step.
     */
    @Query("""
            select coalesce(sum(f.amountPaid), 0) from FeeTransaction f
            where f.membershipId = :membershipId and f.feeTypeId = :feeTypeId
            """)
    BigDecimal sumPaidForFeeType(@Param("membershipId") UUID membershipId, @Param("feeTypeId") UUID feeTypeId);

    @Query("""
            select coalesce(sum(f.amountPaid), 0) from FeeTransaction f
            where f.studentFeeId = :studentFeeId
            """)
    BigDecimal sumPaidForStudentFee(@Param("studentFeeId") UUID studentFeeId);

    /**
     * Rows already reversed, so the UI can hide "undo" on them rather than offering an action the
     * database will refuse.
     */
    @Query("""
            select f.reversalOfTransactionId from FeeTransaction f
            where f.reversalOfTransactionId in :transactionIds
            """)
    List<UUID> findReversedTransactionIds(@Param("transactionIds") List<UUID> transactionIds);

    boolean existsByReversalOfTransactionId(UUID reversalOfTransactionId);

    /** Tenant-scoped lookup. Every read path that serves an academy must go through one of these
     * rather than findById, so a transaction id from another academy resolves to nothing. */
    Optional<FeeTransaction> findByIdAndAcademyId(UUID id, UUID academyId);
}
