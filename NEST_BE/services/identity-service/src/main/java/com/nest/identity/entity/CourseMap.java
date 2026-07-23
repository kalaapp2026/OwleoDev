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

import java.util.UUID;

/**
 * Which courses a trainer/student membership is attached to (PRD 2.3 / 4.4). identity-service
 * owns this table since it must be embedded in the JWT course_map claim on every login/refresh;
 * curriculum-service remains the owner/source of truth for the course catalogue itself, and this
 * row only stores the logical course_id reference (database-per-service - no cross-DB FK).
 */
@Entity
@Table(name = "course_map",
        uniqueConstraints = @UniqueConstraint(columnNames = {"membership_id", "course_id"}),
        indexes = @Index(name = "idx_course_map_membership", columnList = "membership_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CourseMap {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Column(name = "course_id", nullable = false)
    private UUID courseId;
}
