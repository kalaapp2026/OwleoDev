package com.nest.app.enrolment.repository;

import com.nest.app.enrolment.entity.BatchTrainer;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

public interface BatchTrainerRepository extends JpaRepository<BatchTrainer, BatchTrainer.Key> {

    List<BatchTrainer> findByBatchId(UUID batchId);

    /** Batched lookup for a list of batches, so rendering a 40-row batch list doesn't fire 40
     * queries for trainer names. */
    List<BatchTrainer> findByBatchIdIn(Collection<UUID> batchIds);

    /** The batches a trainer is on - study material is open to whoever teaches a batch it is aimed at. */
    List<BatchTrainer> findByTrainerMembershipId(UUID trainerMembershipId);

    void deleteByBatchId(UUID batchId);
}
