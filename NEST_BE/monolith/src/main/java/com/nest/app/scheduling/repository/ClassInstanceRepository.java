package com.nest.app.scheduling.repository;

import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.Collection;
import java.util.List;
import java.util.UUID;

public interface ClassInstanceRepository extends JpaRepository<ClassInstance, UUID> {
    List<ClassInstance> findByBatchIdAndDateBetween(UUID batchId, LocalDate from, LocalDate to);

    /** Calendar's month-view source - every class (any status) across a set of batches in one
     * date range, unlike {@link #findByBatchIdInAndDateBetweenAndStatus} which is fee-slip
     * generation's HELD-only query. */
    List<ClassInstance> findByBatchIdInAndDateBetween(Collection<UUID> batchIds, LocalDate from, LocalDate to);

    List<ClassInstance> findByDateAndStatus(LocalDate date, ClassInstanceStatus status);

    List<ClassInstance> findByBatchIdInAndDateAndStatus(List<UUID> batchIds, LocalDate date, ClassInstanceStatus status);

    List<ClassInstance> findByBatchIdAndDateGreaterThanEqual(UUID batchId, LocalDate date);

    List<ClassInstance> findByBatchId(UUID batchId);

    void deleteByBatchId(UUID batchId);

    /** Fee-slip generation's "classes held in the billing period" source, across every batch a
     * course has - {@code from} is exclusive-ish in practice since callers pass periodStart+1day
     * (see FeeSlipService), so a class held exactly on the previous slip's billing date isn't
     * double-counted into two consecutive periods. */
    List<ClassInstance> findByBatchIdInAndDateBetweenAndStatus(List<UUID> batchIds, LocalDate from, LocalDate to, ClassInstanceStatus status);

    boolean existsByBatchIdAndDateAndStartTime(UUID batchId, LocalDate date, LocalTime startTime);
}
