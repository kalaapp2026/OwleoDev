package com.nest.app.curriculum.repository;

import com.nest.app.curriculum.entity.SyllabusUnit;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface SyllabusUnitRepository extends JpaRepository<SyllabusUnit, UUID> {
    List<SyllabusUnit> findByCourseIdOrderByOrderIndex(UUID courseId);
}
