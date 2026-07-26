package com.nest.app.identity.entity;

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
 * A Trainer's feature checklist scoped to ONE course (supersedes the flat, per-membership
 * {@link FeatureGrant} for trainers). One row per (membership, course, feature_key): the same
 * trainer can hold Attendance on Guitar and nothing on Dance. The coarse @RequiresFeature gate
 * still checks the union across all of a trainer's courses; per-course enforcement (Phase 2)
 * checks the specific course this row belongs to.
 */
@Entity
@Table(name = "course_feature_grants",
        uniqueConstraints = @UniqueConstraint(columnNames = {"membership_id", "course_id", "feature_key"}),
        indexes = @Index(name = "idx_cfg_membership", columnList = "membership_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CourseFeatureGrant {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Column(name = "course_id", nullable = false)
    private UUID courseId;

    @Column(name = "feature_key", nullable = false)
    private String featureKey;

    @Column(name = "granted_by")
    private UUID grantedBy;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;
}
