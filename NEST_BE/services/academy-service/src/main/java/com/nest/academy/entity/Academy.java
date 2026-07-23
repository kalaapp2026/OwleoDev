package com.nest.academy.entity;

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
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.Instant;
import java.util.UUID;

/**
 * Tenant table (PRD 4.4). About-Us content (gallery, founding story, achievements - PRD 3.10)
 * is intentionally NOT modelled here yet - that's Phase 4 scope. Onboarding only auto-creates
 * "an empty About-Us page" in the sense that there's simply nothing to fill in until then.
 */
@Entity
@Table(name = "academies", uniqueConstraints = @UniqueConstraint(columnNames = {"name", "city"}))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Academy {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false)
    private String name;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private AcademyCategory category;

    private String logoUrl;

    @Column(nullable = false)
    private String address;

    @Column(nullable = false)
    private String city;

    @Column(nullable = false)
    private String state;

    @Column(name = "contact_number", nullable = false)
    private String contactNumber;

    private String email;

    @Column(nullable = false)
    @Builder.Default
    private String plan = "STANDARD";

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private AcademyStatus status = AcademyStatus.ACTIVE;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at")
    private Instant updatedAt;
}
