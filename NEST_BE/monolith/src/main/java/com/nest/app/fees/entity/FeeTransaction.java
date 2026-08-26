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
import java.time.LocalDate;
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

    /**
     * The tenant this row belongs to. Stored rather than reached through {@code membershipId} so
     * every ledger query can filter on an indexed column of this table - a cross-academy read is
     * the one bug in a fees module that must not be possible by omission.
     */
    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private FeeCategory category = FeeCategory.REGULAR;

    /** Set for an OTHER row raised from the academy's shared fee-type catalogue. */
    @Column(name = "fee_type_id")
    private UUID feeTypeId;

    /** Set for an OTHER row raised as a one-off against a single student. */
    @Column(name = "student_fee_id")
    private UUID studentFeeId;

    /**
     * Points at the transaction this row cancels out. Undoing a payment posts a compensating
     * negative row instead of deleting the original, so the statement still shows that money was
     * taken and later returned - which is what actually happened.
     */
    @Column(name = "reversal_of_transaction_id")
    private UUID reversalOfTransactionId;

    @Column(name = "reversal_reason")
    private String reversalReason;

    /**
     * The date the money changed hands, which is not always the date it was keyed in. Cash taken
     * on Saturday and entered on Monday belongs to Saturday on the statement and in the
     * received-date filter.
     */
    @Column(name = "occurred_on", nullable = false)
    private LocalDate occurredOn;

    /** True for the compensating row itself, not for the payment it reverses. */
    public boolean isReversal() {
        return reversalOfTransactionId != null;
    }
}
