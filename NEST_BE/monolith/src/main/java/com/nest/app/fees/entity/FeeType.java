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
import org.hibernate.annotations.CreationTimestamp;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/**
 * A named charge an academy raises outside the regular course fee - costume, exam, annual day.
 *
 * <p>Scoped to one academy, never shared across the platform. Two academies both defining a
 * "Costume Fee" is the expected case and they are unrelated records with unrelated amounts, so
 * the uniqueness that matters is {@code (academy_id, name)} and never name on its own.</p>
 */
@Entity
@Table(name = "fee_types",
        uniqueConstraints = @UniqueConstraint(name = "uq_fee_types_academy_name",
                columnNames = {"academy_id", "name"}),
        indexes = @Index(name = "idx_fee_types_academy", columnList = "academy_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class FeeType {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Column(nullable = false, length = 120)
    private String name;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    /**
     * Drives the derived "due" status - an unpaid fee past this date reads as overdue. Null for an
     * open-ended charge with no last date to pay.
     */
    @Column(name = "due_date")
    private LocalDate dueDate;

    /** Pre-selects the mode in the payment recorder. A default, not a restriction. */
    @Enumerated(EnumType.STRING)
    @Column(name = "default_mode", length = 20)
    private FeeMode defaultMode;

    /**
     * Soft-retire rather than delete. A fee type with ledger history behind it has to keep
     * resolving to a name, or every past transaction row loses its label.
     */
    @Column(nullable = false)
    @Builder.Default
    private boolean active = true;

    @Column(name = "created_by")
    private UUID createdBy;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;
}
