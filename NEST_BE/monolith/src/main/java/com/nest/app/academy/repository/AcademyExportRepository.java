package com.nest.app.academy.repository;

import com.nest.app.academy.entity.AcademyExport;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AcademyExportRepository extends JpaRepository<AcademyExport, UUID> {

    List<AcademyExport> findTop10ByAcademyIdOrderByCreatedAtDesc(UUID academyId);
}
