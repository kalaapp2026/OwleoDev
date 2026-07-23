package com.nest.app.fees.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * PRD 3.9.2 - free-form "amount + note" entry, not a rigid full/unpaid toggle. One row per
 * payment; the running balance for a period is computed at read time as
 * {@code course_map.agreedFee - SUM(amountPaid for that membership+course+period)}
 * (see {@link com.nest.app.fees.service.FeesService}), which is what makes partial payments
 * "accumulate against the same billing period" (PRD business rule) instead of overwriting.
 */
@Entity
@Table(name = "fee_transactions", indexes = {
        @Index(name = "idx_fee_tx_membership", columnList = "membership_id"),
        @Index(name = "idx_fee_tx_membership_course_period", columnList = "membership_id, course_id, period")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class FeeTransaction {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Column(name = "course_id", nullable = false)
    private UUID courseId;

    /** e.g. "2026-07" for a monthly cycle, or a term/one-time label. */
    @Column(nullable = false)
    private String period;

    @Column(name = "amount_paid", nullable = false, precision = 12, scale = 2)
    private BigDecimal amountPaid;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private FeeMode mode;

    private String note;

    /** Stamped for audit on every manually-entered (cash/UPI) row (PRD 3.9.2 business rule). */
    @Column(name = "recorded_by", nullable = false)
    private UUID recordedBy;

    @Column(name = "gateway_ref")
    private String gatewayRef;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;
}
