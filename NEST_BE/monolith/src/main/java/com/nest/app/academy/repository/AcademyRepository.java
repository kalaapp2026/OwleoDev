package com.nest.app.academy.repository;

import com.nest.app.academy.entity.Academy;
import com.nest.app.academy.entity.AcademyStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.Instant;
import java.util.UUID;

public interface AcademyRepository extends JpaRepository<Academy, UUID> {
    boolean existsByNameIgnoreCaseAndCityIgnoreCase(String name, String city);

    // ---- Super Admin platform metrics ----

    long countByStatus(AcademyStatus status);

    long countByCreatedAtAfter(Instant since);
}
