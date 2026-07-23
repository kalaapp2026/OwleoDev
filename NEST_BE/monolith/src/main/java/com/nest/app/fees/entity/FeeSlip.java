package com.nest.app.fees.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
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

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/**
 * A computed, persisted fee record for one (membership, course, period) - "the fee slip
 * generated on the billing day". {@code period} ("YYYY-MM" of the billing date) is the same key
 * {@link com.nest.app.fees.entity.FeeTransaction#getPeriod()} uses, so payments recorded through
 * the existing Fees screen naturally net against this amount instead of a separate ledger.
 * {@code classesHeld}/{@code classesAttended} are kept alongside the amount purely so the number
 * can be explained later ("5 of 8 classes attended"), not used in any calculation after the fact.
 */
@Entity
@Table(name = "fee_slips",
        uniqueConstraints = @UniqueConstraint(columnNames = {"membership_id", "course_id", "period"}),
        indexes = {
                @Index(name = "idx_fee_slips_membership", columnList = "membership_id"),
                @Index(name = "idx_fee_slips_course_period", columnList = "course_id, period")
        })
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class FeeSlip {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Column(name = "course_id", nullable = false)
    private UUID courseId;

    @Column(nullable = false)
    private String period;

    @Column(name = "billing_period_start", nullable = false)
    private LocalDate billingPeriodStart;

    @Column(name = "billing_period_end", nullable = false)
    private LocalDate billingPeriodEnd;

    @Column(name = "amount_due", nullable = false, precision = 12, scale = 2)
    private BigDecimal amountDue;

    @Column(name = "classes_held")
    private Integer classesHeld;

    @Column(name = "classes_attended")
    private Integer classesAttended;

    /** How much of {@link #amountDue} is last period's unresolved shortfall rolled in - kept
     * separate from the total purely so the UI can explain the number ("₹1200 due, of which
     * ₹200 carried from last month"), not used in any calculation after being set. */
    @Column(name = "carried_forward_amount", nullable = false, precision = 12, scale = 2)
    @Builder.Default
    private BigDecimal carriedForwardAmount = BigDecimal.ZERO;

    /** OPEN (default) means an unpaid remainder here rolls into the next slip; CLOSED means the
     * Admin/Trainer explicitly wrote off whatever was left unpaid - see FeesService#recordEntry's
     * closePeriod flag. */
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private FeeSlipStatus status = FeeSlipStatus.OPEN;

    @Column(name = "generated_at", nullable = false)
    private Instant generatedAt;
}
