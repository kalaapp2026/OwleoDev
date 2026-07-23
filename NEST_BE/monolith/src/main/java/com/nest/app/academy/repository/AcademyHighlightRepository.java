package com.nest.app.academy.repository;

import com.nest.app.academy.entity.AcademyHighlight;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AcademyHighlightRepository extends JpaRepository<AcademyHighlight, UUID> {
    List<AcademyHighlight> findByAcademyIdOrderByOrderIndex(UUID academyId);
}
