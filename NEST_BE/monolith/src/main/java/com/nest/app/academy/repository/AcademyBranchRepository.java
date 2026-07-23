package com.nest.app.academy.repository;

import com.nest.app.academy.entity.AcademyBranch;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AcademyBranchRepository extends JpaRepository<AcademyBranch, UUID> {
    List<AcademyBranch> findByAcademyIdOrderByOrderIndex(UUID academyId);
}
