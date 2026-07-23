package com.nest.identity.entity;

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
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.UUID;

/**
 * The per-trainer feature checklist (PRD 2.3 / 3.5) - one row per (membership, feature_key).
 * {@code grantedBy} is the membership id of whoever ticked this feature ON, which is what enforces
 * cascading delegation: a Trainer can only hand out features present in their own grant set.
 */
@Entity
@Table(name = "feature_grants",
        uniqueConstraints = @UniqueConstraint(columnNames = {"membership_id", "feature_key"}),
        indexes = @Index(name = "idx_feature_grants_membership", columnList = "membership_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class FeatureGrant {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Column(name = "feature_key", nullable = false)
    private String featureKey;

    @Column(name = "granted_by")
    private UUID grantedBy;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;
}
