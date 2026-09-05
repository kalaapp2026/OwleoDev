package com.nest.app.curriculum.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.io.Serializable;
import java.util.UUID;

/**
 * One student a {@link StudyMaterialVisibility#SELECTED} material was shared with.
 *
 * <p>Read only when the parent material says SELECTED. On an ALL material these rows are ignored
 * rather than consulted, so a material switched from SELECTED back to ALL immediately means "the
 * whole batch" without needing its old selection cleaned up first.
 *
 * <p>Keyed by membership, not user: the same person at two academies is two memberships, and the
 * material belongs to exactly one of them.
 */
@Entity
@Table(name = "study_material_students", indexes =
        @Index(name = "idx_study_material_students_membership", columnList = "membership_id"))
@IdClass(StudyMaterialStudent.Key.class)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class StudyMaterialStudent {

    @Id
    @Column(name = "material_id", nullable = false)
    private UUID materialId;

    @Id
    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @EqualsAndHashCode
    public static class Key implements Serializable {
        private UUID materialId;
        private UUID membershipId;
    }
}
