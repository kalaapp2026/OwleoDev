package com.nest.app.curriculum.repository;

import com.nest.app.curriculum.entity.StudyMaterialStudent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface StudyMaterialStudentRepository
        extends JpaRepository<StudyMaterialStudent, StudyMaterialStudent.Key> {

    List<StudyMaterialStudent> findByMaterialId(UUID materialId);

    /** Batched, so listing a batch's files does not fire one query per file. */
    List<StudyMaterialStudent> findByMaterialIdIn(List<UUID> materialIds);

    boolean existsByMaterialIdAndMembershipId(UUID materialId, UUID membershipId);

    /** flush + clear because the selection is replaced wholesale: the deletes must land before
     * the re-inserts, or the two collide on the composite primary key. */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("delete from StudyMaterialStudent s where s.materialId = :materialId")
    void deleteByMaterialId(@Param("materialId") UUID materialId);
}
