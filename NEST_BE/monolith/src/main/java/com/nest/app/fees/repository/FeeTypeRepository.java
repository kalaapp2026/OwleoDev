package com.nest.app.fees.repository;

import com.nest.app.fees.entity.FeeType;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface FeeTypeRepository extends JpaRepository<FeeType, UUID> {

    List<FeeType> findByAcademyIdAndActiveTrueOrderByNameAsc(UUID academyId);

    List<FeeType> findByAcademyIdOrderByNameAsc(UUID academyId);

    /**
     * Always by id AND academy. A fee type id arriving from a client is untrusted input, and
     * findById alone would happily return another tenant's row.
     */
    Optional<FeeType> findByIdAndAcademyId(UUID id, UUID academyId);

    boolean existsByAcademyIdAndNameIgnoreCase(UUID academyId, String name);
}
