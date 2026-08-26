package com.nest.app.fees.entity;

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

import java.util.UUID;

/**
 * Which batches a {@link FeeType} applies to.
 *
 * <p>A join table rather than a single {@code batchId} column because a costume fee usually hits
 * several batches at once - and because the selector auto-picks the batch when a type is bound to
 * exactly one, which is a count, not a nullable column.</p>
 */
@Entity
@Table(name = "fee_type_batches",
        uniqueConstraints = @UniqueConstraint(name = "uq_fee_type_batches",
                columnNames = {"fee_type_id", "batch_id"}),
        indexes = @Index(name = "idx_fee_type_batches_batch", columnList = "batch_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class FeeTypeBatch {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "fee_type_id", nullable = false)
    private UUID feeTypeId;

    @Column(name = "batch_id", nullable = false)
    private UUID batchId;
}
