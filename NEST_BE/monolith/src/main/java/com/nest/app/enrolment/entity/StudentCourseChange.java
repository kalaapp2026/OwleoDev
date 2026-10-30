package com.nest.app.enrolment.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/**
 * A student's move from one course to another on a future date. Scheduled now, applied by a job on
 * {@code effectiveOn}: until then nothing about the student changes, so this month's fee slip stays as it
 * was issued.
 */
@Entity
@Table(name = "student_course_changes")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class StudentCourseChange {

    public enum Status { PENDING, APPLIED, CANCELLED }

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Column(name = "from_course_id", nullable = false)
    private UUID fromCourseId;

    @Column(name = "to_course_id", nullable = false)
    private UUID toCourseId;

    @Column(name = "effective_on", nullable = false)
    private LocalDate effectiveOn;

    /** Batches of the new course to place the student in when it takes effect, comma-separated. */
    @Column(name = "to_batch_ids", length = 2000)
    private String toBatchIds;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    @Builder.Default
    private Status status = Status.PENDING;

    @Column(name = "created_by", nullable = false)
    private UUID createdBy;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "applied_at")
    private Instant appliedAt;
}
