package com.nest.app.billing.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
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
 * What one academy owes NEST for one month of platform use.
 *
 * <p>Not to be confused with {@code fee_slips}, which is an academy billing its own students -
 * same vocabulary, opposite direction of money.
 */
@Entity
@Table(name = "academy_invoices",
        uniqueConstraints = @UniqueConstraint(columnNames = {"academy_id", "period"}))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AcademyInvoice {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    /** 'YYYY-MM'. Unique per academy, which is what makes re-running generation for a month
     * idempotent instead of double-charging. */
    @Column(nullable = false, length = 7)
    private String period;

    @Column(name = "plan_code", nullable = false, length = 40)
    private String planCode;

    /** Copied from the plan when the invoice is issued and never re-read, so changing a plan's
     * price cannot silently alter invoices already sent. */
    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private InvoiceStatus status = InvoiceStatus.DUE;

    @Column(name = "issued_on", nullable = false)
    private LocalDate issuedOn;

    @Column(name = "due_on", nullable = false)
    private LocalDate dueOn;

    @Column(name = "paid_at")
    private Instant paidAt;

    @Column(name = "paid_amount", precision = 12, scale = 2)
    private BigDecimal paidAmount;

    @Column(name = "payment_method", length = 30)
    private String paymentMethod;

    @Column(name = "payment_ref", length = 120)
    private String paymentRef;

    @Column(length = 500)
    private String note;

    /** Which Super Admin recorded the payment - payments are entered by hand today, so who
     * entered it is part of the record. */
    @Column(name = "recorded_by")
    private UUID recordedBy;

    @Column(name = "created_at", insertable = false, updatable = false)
    private Instant createdAt;

    /** Overdue is DUE plus time, not a status someone sets - deriving it means it can never go
     * stale relative to the date. */
    public boolean isOverdue(LocalDate today) {
        return status == InvoiceStatus.DUE && dueOn.isBefore(today);
    }
}
