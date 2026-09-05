package com.nest.app.identity.entity;

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
 * Narrows a trainer's access on one course down to specific batches - "Attendance, but only for
 * Batch A".
 *
 * <p>Complements {@code course_feature_grants}, which records WHICH features they hold on a
 * course; this records WHERE those features apply within it.
 *
 * <p><b>Absence means everything.</b> No rows for a (membership, course) pair is "every batch on
 * that course", not "no batches" - which is the access every trainer had before this table
 * existed, and why the migration seeds nothing.
 */
@Entity
@Table(name = "trainer_course_batches", indexes =
        @Index(name = "idx_trainer_course_batches_membership", columnList = "membership_id"))
@IdClass(TrainerCourseBatch.Key.class)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class TrainerCourseBatch {

    @Id
    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Id
    @Column(name = "course_id", nullable = false)
    private UUID courseId;

    @Id
    @Column(name = "batch_id", nullable = false)
    private UUID batchId;

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @EqualsAndHashCode
    public static class Key implements Serializable {
        private UUID membershipId;
        private UUID courseId;
        private UUID batchId;
    }
}
