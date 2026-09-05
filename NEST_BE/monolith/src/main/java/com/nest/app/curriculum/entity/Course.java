package com.nest.app.curriculum.entity;

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
import org.hibernate.annotations.UpdateTimestamp;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * PRD 3.3. Every other ERP object (trainer mapping, batch, fees, syllabus) hangs off a course.
 * Admin-only, never delegable to Trainers. No hard-delete endpoint is exposed anywhere on
 * purpose - "cannot be deleted once students are enrolled, only deactivated" (PRD business rule)
 * is enforced simply by never offering a DELETE at all, only the status toggle.
 */
@Entity
@Table(name = "courses", indexes = @Index(name = "idx_courses_academy", columnList = "academy_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Course {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private CourseCategory category;

    @Column(nullable = false)
    private String name;

    @Column(columnDefinition = "text")
    private String description;

    @Column(name = "duration_level")
    private String durationLevel;

    /** Base/subscription fee - required for FIXED and HYBRID, unused for PER_CLASS (see feePerClass). */
    @Column(name = "default_fee", precision = 12, scale = 2)
    private BigDecimal defaultFee;

    @Enumerated(EnumType.STRING)
    @Column(name = "fee_cycle", nullable = false)
    private FeeCycle feeCycle;

    /** NEST Course Fee Calculation Spec §2/§3 - how this course's fee is calculated. Config
     * fields below are only meaningful for the model they belong to; the create/update service
     * validates that the right ones are present for whichever model is chosen. */
    @Enumerated(EnumType.STRING)
    @Column(name = "fee_model", nullable = false)
    @Builder.Default
    private FeeModel feeModel = FeeModel.FIXED;

    /** PER_CLASS only - rate charged per class attended. */
    @Column(name = "fee_per_class", precision = 12, scale = 2)
    private BigDecimal feePerClass;

    /** HYBRID only - classes expected in a billing period, used to compute the attendance threshold. */
    @Column(name = "hybrid_expected_classes_per_period")
    private Integer hybridExpectedClassesPerPeriod;

    /** HYBRID only - minimum classes attended to be charged the full (above-threshold) rate. */
    @Column(name = "hybrid_threshold_attendance")
    private Integer hybridThresholdAttendance;

    /** HYBRID only - % of defaultFee charged when attendance meets/exceeds the threshold (usually 100). */
    @Column(name = "hybrid_fee_above_threshold_percent")
    @Builder.Default
    private Integer hybridFeeAboveThresholdPercent = 100;

    /** HYBRID only - % of defaultFee charged when attendance is below the threshold (e.g. 50). */
    @Column(name = "hybrid_fee_below_threshold_percent")
    private Integer hybridFeeBelowThresholdPercent;

    /** HYBRID only, optional - floor amount charged even at zero attendance. */
    @Column(name = "hybrid_min_fee_amount", precision = 12, scale = 2)
    private BigDecimal hybridMinFeeAmount;

    /** Day of month (1-31) fee slips are generated on, e.g. 2 means "bill on the 2nd, covering
     * the period from last month's 2nd to this month's 2nd". Null means no auto-billing is
     * configured for this course - fees stay purely manual (existing FeesService behaviour). */
    @Column(name = "billing_day_of_month")
    private Integer billingDayOfMonth;

    /** Day of month (1-31) an unpaid slip becomes overdue, which is what flips a student's status
     * to "Due" and triggers the payment reminder. Distinct from billingDayOfMonth (when the slip
     * is raised) - a course typically bills on the 5th and falls due on the 10th. */
    @Column(name = "due_day_of_month")
    private Integer dueDayOfMonth;

    /** Accepted payment methods as a comma-separated set of CASH / UPI / GATEWAY. Persisted
     * inline rather than as a child table - the set is fixed and tiny, and is only ever read
     * alongside the course itself. Use {@link #getPaymentMethodSet()} rather than splitting the
     * raw string at call sites. */
    @Column(name = "payment_methods", nullable = false)
    @Builder.Default
    private String paymentMethods = "CASH";

    /** Which of the app's icons this course renders with. Keys come from the frontend's icon set
     * (e.g. {@code guitar}, {@code bharatanatyam}); the backend stores but never interprets them,
     * so adding art needs no migration here. */
    @Column(name = "icon_key")
    private String iconKey;

    @Column(name = "thumbnail_url")
    private String thumbnailUrl;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private CourseStatus status = CourseStatus.ACTIVE;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at")
    private Instant updatedAt;

    /**
     * The accepted payment methods as a set. Blank entries are dropped so a stray trailing comma
     * can't produce an empty method name that no payment would ever match.
     */
    public java.util.Set<String> getPaymentMethodSet() {
        if (paymentMethods == null || paymentMethods.isBlank()) {
            return java.util.Set.of();
        }
        return java.util.Arrays.stream(paymentMethods.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .collect(java.util.stream.Collectors.toCollection(java.util.LinkedHashSet::new));
    }
}
