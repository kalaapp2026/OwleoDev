package com.nest.app.fees.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
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
 * One online checkout attempt. It is written before the student pays and pins what is being paid,
 * for how much and by whom, so that the gateway's later "this order was paid" - from the browser
 * or from its webhook, whichever lands first - has exactly one thing to settle.
 *
 * <p>The ledger stays the source of truth for what is owed: an order only becomes a
 * {@link FeeTransaction} when the gateway confirms it, and {@link #feeTransactionId} records which
 * one, so a confirmation that arrives twice cannot post the money twice.</p>
 */
@Entity
@Table(name = "payment_orders")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PaymentOrder {

    public enum Status { CREATED, PAID, FAILED }

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private FeeCategory category;

    @Column(name = "course_id")
    private UUID courseId;

    private String period;

    @Column(name = "fee_type_id")
    private UUID feeTypeId;

    @Column(name = "student_fee_id")
    private UUID studentFeeId;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(name = "amount_paise", nullable = false)
    private long amountPaise;

    @Column(nullable = false)
    @Builder.Default
    private String currency = "INR";

    @Column(nullable = false)
    @Builder.Default
    private String provider = "RAZORPAY";

    @Column(name = "provider_order_id", nullable = false)
    private String providerOrderId;

    @Column(name = "provider_payment_id")
    private String providerPaymentId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private Status status = Status.CREATED;

    @Column(name = "fee_transaction_id")
    private UUID feeTransactionId;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    @Column(name = "paid_at")
    private Instant paidAt;
}
