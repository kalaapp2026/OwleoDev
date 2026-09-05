package com.nest.app.enrolment.entity;

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

import java.time.LocalDate;
import java.util.UUID;

/** PRD 3.6. Splits a course's students into deliverable groups. */
@Entity
@Table(name = "batches", indexes = @Index(name = "idx_batches_course", columnList = "course_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Batch {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "course_id", nullable = false)
    private UUID courseId;

    @Column(nullable = false)
    private String name;

    private String description;

    @Enumerated(EnumType.STRING)
    @Column(name = "batch_type", nullable = false)
    private BatchType batchType;

    /**
     * The batch's primary trainer (PRD 3.6). A batch may have several - see {@code batch_trainers}
     * - but this one stays the single value every existing query resolves a trainer name from, and
     * is always mirrored into that table.
     */
    @Column(name = "trainer_membership_id")
    private UUID trainerMembershipId;

    /** The day classes begin. Null on batches created before this was captured. */
    @Column(name = "start_date")
    private LocalDate startDate;

    /** Only meaningful for a TEMPORARY batch, which runs between two dates; a Regular batch runs
     * until it is deactivated. Null means open-ended. */
    @Column(name = "end_date")
    private LocalDate endDate;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private BatchStatus status = BatchStatus.ACTIVE;
}
