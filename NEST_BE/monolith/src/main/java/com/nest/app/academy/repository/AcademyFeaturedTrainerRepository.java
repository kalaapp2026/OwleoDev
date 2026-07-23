package com.nest.app.academy.repository;

import com.nest.app.academy.entity.AcademyFeaturedTrainer;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AcademyFeaturedTrainerRepository extends JpaRepository<AcademyFeaturedTrainer, UUID> {
    List<AcademyFeaturedTrainer> findByAcademyIdOrderByOrderIndex(UUID academyId);
}
