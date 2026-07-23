package com.nest.app.curriculum.repository;

import com.nest.app.curriculum.entity.MaterialAttachment;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface MaterialAttachmentRepository extends JpaRepository<MaterialAttachment, UUID> {
    List<MaterialAttachment> findBySyllabusUnitIdOrderByUploadedAt(UUID syllabusUnitId);

    void deleteBySyllabusUnitId(UUID syllabusUnitId);
}
