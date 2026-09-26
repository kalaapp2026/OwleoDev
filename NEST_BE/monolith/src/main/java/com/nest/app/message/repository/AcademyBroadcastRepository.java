package com.nest.app.message.repository;

import com.nest.app.message.entity.AcademyBroadcast;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AcademyBroadcastRepository extends JpaRepository<AcademyBroadcast, UUID> {

    List<AcademyBroadcast> findByAcademyIdOrderByCreatedAtDesc(UUID academyId);
}
