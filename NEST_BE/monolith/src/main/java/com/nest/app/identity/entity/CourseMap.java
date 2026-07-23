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

import java.math.BigDecimal;
import java.util.UUID;

/**
 * Which courses a trainer/student membership is attached to (PRD 2.3 / 4.4). Doubles as the
 * per-student "agreed fee" record (PRD 3.4: "Fee... defaults to the Course's Default Fee;
 * editable at creation and later from the student's profile") - {@code agreedFee} stays null for
 * Trainer course-map rows, which have no fee concept.
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

    /** Null for Trainer course-map rows. Set at student enrolment, defaulting to the course's
     * default_fee, editable per-student thereafter (sibling discount, scholarship, etc.). */
    @Column(name = "agreed_fee", precision = 12, scale = 2)
    private BigDecimal agreedFee;
}
