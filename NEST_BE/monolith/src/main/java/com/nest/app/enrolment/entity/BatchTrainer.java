package com.nest.app.enrolment.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.io.Serializable;
import java.util.UUID;

/**
 * A trainer assigned to a batch. A batch can be taught by more than one (PRD 3.6) - a
 * Bharatanatyam batch commonly has a lead and an accompanist.
 *
 * <p>The batch's primary trainer is also mirrored here, so anything wanting "every trainer on this
 * batch" reads one table instead of unioning {@code Batch.trainerMembershipId} with this one.
 */
@Entity
@Table(name = "batch_trainers", indexes =
        @Index(name = "idx_batch_trainers_membership", columnList = "trainer_membership_id"))
@IdClass(BatchTrainer.Key.class)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class BatchTrainer {

    @Id
    @Column(name = "batch_id", nullable = false)
    private UUID batchId;

    @Id
    @Column(name = "trainer_membership_id", nullable = false)
    private UUID trainerMembershipId;

    /** Composite key - the pair is the identity, so assigning the same trainer twice is a
     * primary-key conflict rather than a duplicate row. */
    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @EqualsAndHashCode
    public static class Key implements Serializable {
        private UUID batchId;
        private UUID trainerMembershipId;
    }
}
