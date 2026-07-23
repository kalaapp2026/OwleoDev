package com.nest.academy.repository;

import com.nest.academy.entity.Academy;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface AcademyRepository extends JpaRepository<Academy, UUID> {
    boolean existsByNameIgnoreCaseAndCityIgnoreCase(String name, String city);
}
