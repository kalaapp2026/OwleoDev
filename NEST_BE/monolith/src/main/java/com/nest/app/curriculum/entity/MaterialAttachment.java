package com.nest.app.curriculum.entity;

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
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.UUID;

/** One PDF/image attachment on a {@link SyllabusUnit} - a unit can carry several (a worksheet
 * plus a diagram, several pages scanned separately, etc.), unlike the single-attachment model
 * this replaced. Mirrors {@link Track}'s own one-to-many shape for song attachments. */
@Entity
@Table(name = "syllabus_unit_materials", indexes = @Index(name = "idx_syllabus_unit_materials_unit", columnList = "syllabus_unit_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MaterialAttachment {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "syllabus_unit_id", nullable = false)
    private UUID syllabusUnitId;

    @Column(nullable = false)
    private String url;

    @Enumerated(EnumType.STRING)
    @Column(name = "material_type", nullable = false)
    private ReferenceMaterialType materialType;

    @Column(name = "content_type")
    private String contentType;

    @CreationTimestamp
    @Column(name = "uploaded_at", updatable = false)
    private Instant uploadedAt;
}
