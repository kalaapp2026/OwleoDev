package com.nest.app.fees.repository;

import com.nest.app.fees.entity.FeeTypeBatch;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface FeeTypeBatchRepository extends JpaRepository<FeeTypeBatch, UUID> {

    List<FeeTypeBatch> findByFeeTypeId(UUID feeTypeId);

    List<FeeTypeBatch> findByFeeTypeIdIn(List<UUID> feeTypeIds);

    List<FeeTypeBatch> findByBatchId(UUID batchId);

    /** Which fee types apply to any of these batches - a student sits in several. */
    List<FeeTypeBatch> findByBatchIdIn(List<UUID> batchIds);

    /**
     * Bulk delete, not the derived deleteBy. A derived delete loads the rows and queues per-row
     * removals, and Hibernate flushes inserts before deletes - so re-saving an unchanged binding
     * in the same transaction trips the unique constraint against the row being deleted.
     *
     * <p>flushAutomatically matters as much as clearAutomatically: without it, entities inserted
     * earlier in the transaction are still pending when the clear discards them, and the writes
     * vanish silently. See ModifyingQueryFlushContractTest, which asserts both flags are present
     * on every @Modifying query in the codebase.</p>
     */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("delete from FeeTypeBatch b where b.feeTypeId = :feeTypeId")
    void deleteAllForFeeType(@Param("feeTypeId") UUID feeTypeId);
}
