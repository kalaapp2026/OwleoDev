package com.nest.app.curriculum.entity;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
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

import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

/** PRD 3.11 - a piece of course material (description + zero or more PDF/image attachments, see
 * {@link MaterialAttachment}, + zero or more song attachments, see {@link Track}). Targeting:
 * empty {@link #batchIds} means "the whole course" (anyone enrolled via course_map sees it); one
 * or more means "only these batches' students/trainer" - set at creation via a multi-select, not
 * a single batch. */
@Entity
@Table(name = "syllabus_units", indexes = @Index(name = "idx_syllabus_course", columnList = "course_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class SyllabusUnit {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "course_id", nullable = false)
    private UUID courseId;

    @ElementCollection
    @CollectionTable(name = "syllabus_unit_batches", joinColumns = @JoinColumn(name = "syllabus_unit_id"))
    @Column(name = "batch_id")
    @Builder.Default
    private Set<UUID> batchIds = new HashSet<>();

    @Column(nullable = false)
    private String title;

    @Column(columnDefinition = "text")
    private String description;

    @Column(name = "order_index", nullable = false)
    private int orderIndex;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private SyllabusUnitStatus status = SyllabusUnitStatus.NOT_STARTED;
}
