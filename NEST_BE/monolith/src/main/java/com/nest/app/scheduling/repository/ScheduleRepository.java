package com.nest.app.scheduling.repository;

import com.nest.app.scheduling.entity.Schedule;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface ScheduleRepository extends JpaRepository<Schedule, UUID> {
    List<Schedule> findByBatchId(UUID batchId);

    List<Schedule> findByBatchIdAndEffectiveToIsNull(UUID batchId);

    /** The slots in force today for a whole page of batches - one query, not one per batch. */
    List<Schedule> findByBatchIdInAndEffectiveToIsNull(java.util.Collection<UUID> batchIds);

    void deleteByBatchId(UUID batchId);
}
