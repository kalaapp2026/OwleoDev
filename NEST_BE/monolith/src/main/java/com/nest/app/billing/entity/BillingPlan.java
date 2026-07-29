package com.nest.app.billing.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * What a subscription tier costs. A table rather than an enum so pricing can change without a
 * deploy - and because an invoice copies the amount at issue time, a price change never rewrites
 * what an academy was already billed.
 */
@Entity
@Table(name = "billing_plans")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class BillingPlan {

    @Id
    @Column(length = 40)
    private String code;

    @Column(name = "display_name", nullable = false, length = 80)
    private String displayName;

    @Column(name = "monthly_price", nullable = false, precision = 12, scale = 2)
    private BigDecimal monthlyPrice;

    /** Soft caps - surfaced in the console as "outgrown its plan", never enforced at the point of
     * creating a student or course. Blocking a class from being set up over a billing limit is a
     * bad experience; the operator should have the upgrade conversation instead. */
    @Column(name = "max_students")
    private Integer maxStudents;

    @Column(name = "max_trainers")
    private Integer maxTrainers;

    @Column(nullable = false)
    @Builder.Default
    private boolean active = true;

    @Column(name = "created_at", insertable = false, updatable = false)
    private Instant createdAt;
}
