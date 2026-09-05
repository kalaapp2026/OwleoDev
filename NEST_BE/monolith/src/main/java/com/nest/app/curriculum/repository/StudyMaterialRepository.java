package com.nest.app.curriculum.repository;

import com.nest.app.curriculum.entity.StudyMaterial;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

public interface StudyMaterialRepository extends JpaRepository<StudyMaterial, UUID> {

    List<StudyMaterial> findByBatchIdOrderByUploadedAtDesc(UUID batchId);

    /** File counts and last-updated for a whole batch list in one query - the home screen shows
     * both per row, which would otherwise be two queries per batch. */
    List<StudyMaterial> findByBatchIdIn(Collection<UUID> batchIds);

    void deleteByBatchId(UUID batchId);
}
