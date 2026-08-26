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
 * A one-off charge raised against a single named student rather than a batch.
 *
 * <p>Distinct from {@link FeeType}: there is no catalogue entry and no batch binding: it exists
 * only for this one person.</p>
 *
 * <p>{@code academyId} is stored here rather than reached through {@code membershipId} on purpose.
 * This is the fee record most exposed to a cross-tenant leak, being the only one keyed solely by
 * student, so the tenant filter has to be a column queries can index and the API can assert on
 * directly.</p>
 */
@Entity
@Table(name = "student_fees", indexes = {
        @Index(name = "idx_student_fees_academy", columnList = "academy_id"),
        @Index(name = "idx_student_fees_membership", columnList = "membership_id")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class StudentFee {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Column(nullable = false, length = 120)
    private String name;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(name = "due_date")
    private LocalDate dueDate;

    @Enumerated(EnumType.STRING)
    @Column(name = "default_mode", length = 20)
    private FeeMode defaultMode;

    @Column(length = 500)
    private String note;

    @Column(name = "created_by")
    private UUID createdBy;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;
}
