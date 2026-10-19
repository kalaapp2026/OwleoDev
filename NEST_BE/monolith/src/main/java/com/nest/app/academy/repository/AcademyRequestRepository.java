package com.nest.app.academy.repository;

import com.nest.app.academy.entity.AcademyRequest;
import com.nest.app.academy.entity.AcademyRequestStatus;
import com.nest.app.academy.entity.AcademyRequestType;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AcademyRequestRepository extends JpaRepository<AcademyRequest, UUID> {

    List<AcademyRequest> findByAcademyIdOrderByCreatedAtDesc(UUID academyId);

    List<AcademyRequest> findByStatusOrderByCreatedAtDesc(AcademyRequestStatus status);

    List<AcademyRequest> findAllByOrderByCreatedAtDesc();

    boolean existsByAcademyIdAndTypeAndStatus(UUID academyId, AcademyRequestType type, AcademyRequestStatus status);
}
