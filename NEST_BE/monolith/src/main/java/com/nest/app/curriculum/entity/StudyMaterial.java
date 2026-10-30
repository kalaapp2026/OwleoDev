package com.nest.app.curriculum.entity;

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
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.UUID;

/**
 * A file shared with an audience - this week's chord chart, a backing track, a photo of the board. The
 * audience is a set of courses (every enrolled student) and/or batches (the students in them), kept in
 * {@code study_material_targets}.
 *
 * <p>This replaced the old per-course syllabus units (V29): material hangs off a batch, not off an
 * ordered curriculum structure. The old {@code syllabus_*} tables are kept in the database but
 * nothing reads them.
 */
@Entity
@Table(name = "study_materials", indexes = {
        @Index(name = "idx_study_materials_batch", columnList = "batch_id"),
        @Index(name = "idx_study_materials_batch_uploaded", columnList = "batch_id, uploaded_at DESC")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class StudyMaterial {

    @Id
    @GeneratedValue
    private UUID id;

    /** The material's "home batch": the first batch it was aimed at, or null for a file aimed only at
     * courses. Kept for older readers; the audience itself is {@link #targets}. */
    @Column(name = "batch_id")
    private UUID batchId;

    /** Who it is for: courses and/or batches. Never empty for a stored material. */
    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "study_material_targets", joinColumns = @JoinColumn(name = "material_id"))
    @BatchSize(size = 100)
    @Builder.Default
    private Set<MaterialTarget> targets = new LinkedHashSet<>();

    @Column(nullable = false)
    private String title;

    /** A one-line note for students. Capped short on purpose - the file is the content. */
    private String description;

    @Column(nullable = false)
    private String url;

    @Column(name = "file_name", nullable = false)
    private String fileName;

    @Column(name = "content_type")
    private String contentType;

    @Enumerated(EnumType.STRING)
    @Column(name = "file_type", nullable = false)
    private StudyMaterialType fileType;

    @Column(name = "size_bytes", nullable = false)
    @Builder.Default
    private long sizeBytes = 0;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private StudyMaterialPermission permission = StudyMaterialPermission.DOWNLOADABLE;

    /**
     * Whether the whole batch sees this, or only the students named in
     * {@code study_material_students}.
     *
     * <p>Defaults to ALL so every material uploaded before this column existed keeps meaning
     * exactly what it meant.
     */
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private StudyMaterialVisibility visibility = StudyMaterialVisibility.ALL;

    /** The user who uploaded it, shown to students as "shared by". */
    @Column(name = "uploaded_by", nullable = false)
    private UUID uploadedBy;

    @CreationTimestamp
    @Column(name = "uploaded_at", nullable = false, updatable = false)
    private Instant uploadedAt;
}
