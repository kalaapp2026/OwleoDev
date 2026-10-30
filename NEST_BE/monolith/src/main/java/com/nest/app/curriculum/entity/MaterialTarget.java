package com.nest.app.curriculum.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import lombok.AllArgsConstructor;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.UUID;

/** One entry of a material's audience: a course or a batch. Value-equal, so a set holds it once. */
@Embeddable
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@EqualsAndHashCode
public class MaterialTarget {

    @Enumerated(EnumType.STRING)
    @Column(name = "target_type", nullable = false, length = 10)
    private StudyMaterialTargetType targetType;

    @Column(name = "target_id", nullable = false)
    private UUID targetId;

    public static MaterialTarget course(UUID courseId) {
        return new MaterialTarget(StudyMaterialTargetType.COURSE, courseId);
    }

    public static MaterialTarget batch(UUID batchId) {
        return new MaterialTarget(StudyMaterialTargetType.BATCH, batchId);
    }

    public boolean isCourse() {
        return targetType == StudyMaterialTargetType.COURSE;
    }

    public boolean isBatch() {
        return targetType == StudyMaterialTargetType.BATCH;
    }
}
