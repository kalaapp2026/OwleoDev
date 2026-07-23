package com.nest.app.enrolment.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.UUID;

/** Student roster per batch (PRD 3.6). A membership may belong to only one REGULAR batch per
 * course at a time - enforced in {@link com.nest.app.enrolment.service.BatchService}, not here,
 * since it requires cross-referencing the owning Batch's courseId. */
@Entity
@Table(name = "batch_members",
        uniqueConstraints = @UniqueConstraint(columnNames = {"batch_id", "membership_id"}),
        indexes = {
                @Index(name = "idx_batch_members_batch", columnList = "batch_id"),
                @Index(name = "idx_batch_members_membership", columnList = "membership_id")
        })
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class BatchMember {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "batch_id", nullable = false)
    private UUID batchId;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @CreationTimestamp
    @Column(name = "joined_at", updatable = false)
    private Instant joinedAt;
}
