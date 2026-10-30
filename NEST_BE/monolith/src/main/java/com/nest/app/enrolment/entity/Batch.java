package com.nest.app.enrolment.entity;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.BatchSize;

import java.time.LocalDate;
import java.util.LinkedHashSet;
import java.util.Set;
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

    /** The batch's PRIMARY course - the first one picked. Kept as a plain column so every query that
     * reads one course keeps working; the full set a batch covers is {@link #allCourseIds()}. */
    @Column(name = "course_id", nullable = false)
    private UUID courseId;

    /** Every course the batch covers, the primary included (table {@code batch_courses}). A batch of
     * Basic + Intermediate + Advanced learners lists all three. Never read this directly for
     * permissions or display - go through {@link #allCourseIds()}, which also guarantees the primary. */
    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "batch_courses", joinColumns = @JoinColumn(name = "batch_id"))
    @Column(name = "course_id", nullable = false)
    @BatchSize(size = 100)
    @Builder.Default
    private Set<UUID> courseIds = new LinkedHashSet<>();

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

    /** Meet / Zoom / Teams link for an online class; null when the batch meets in person. */
    @Column(name = "meeting_link", length = 500)
    private String meetingLink;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private BatchStatus status = BatchStatus.ACTIVE;

    /** Every course this batch covers, primary first. Always contains {@link #courseId}, even for a
     * batch whose collection row is missing, so callers never have to special-case "no extras". */
    public Set<UUID> allCourseIds() {
        Set<UUID> all = new LinkedHashSet<>();
        if (courseId != null) {
            all.add(courseId);
        }
        if (courseIds != null) {
            all.addAll(courseIds);
        }
        return all;
    }

    /** True when {@code course} is one of the courses this batch covers. */
    public boolean coversCourse(UUID course) {
        return course != null && (course.equals(courseId) || (courseIds != null && courseIds.contains(course)));
    }

    /** Replaces the covered courses, keeping {@link #courseId} as the first (primary) one. */
    public void setCourses(java.util.List<UUID> ordered) {
        this.courseId = ordered.get(0);
        if (this.courseIds == null) {
            this.courseIds = new LinkedHashSet<>();
        }
        this.courseIds.clear();
        this.courseIds.addAll(ordered);
    }
}
