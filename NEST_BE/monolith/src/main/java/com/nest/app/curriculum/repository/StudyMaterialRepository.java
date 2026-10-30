package com.nest.app.curriculum.repository;

import com.nest.app.curriculum.entity.StudyMaterial;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

public interface StudyMaterialRepository extends JpaRepository<StudyMaterial, UUID> {

    /**
     * Every material aimed at any of these batches or any of these courses, each once. The candidates
     * for a listing; who of them the caller may actually open is decided afterwards, per material.
     * Callers pass a placeholder id rather than an empty collection.
     */
    @Query("""
            select distinct m from StudyMaterial m join m.targets t
            where (t.targetType = com.nest.app.curriculum.entity.StudyMaterialTargetType.BATCH and t.targetId in :batchIds)
               or (t.targetType = com.nest.app.curriculum.entity.StudyMaterialTargetType.COURSE and t.targetId in :courseIds)
            """)
    List<StudyMaterial> findForTargets(@Param("batchIds") Collection<UUID> batchIds,
                                       @Param("courseIds") Collection<UUID> courseIds);
}
