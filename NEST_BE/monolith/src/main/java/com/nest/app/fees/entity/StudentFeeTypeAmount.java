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
import org.hibernate.annotations.UpdateTimestamp;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * What one student owes for a shared {@link FeeType}, when that differs from the type's own amount -
 * a sibling discount, a scholarship. Read in place of the type's amount for that student alone; the
 * type itself, and every other student, are untouched.
 */
@Entity
@Table(name = "student_fee_type_amounts",
        uniqueConstraints = @UniqueConstraint(name = "uq_student_fee_type_amounts",
                columnNames = {"membership_id", "fee_type_id"}),
        indexes = {
                @Index(name = "idx_student_fee_type_amounts_academy", columnList = "academy_id"),
                @Index(name = "idx_student_fee_type_amounts_type", columnList = "fee_type_id")
        })
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class StudentFeeTypeAmount {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Column(name = "fee_type_id", nullable = false)
    private UUID feeTypeId;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(name = "updated_by")
    private UUID updatedBy;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;
}
