package com.nest.identity.repository;

import com.nest.identity.entity.CourseMap;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface CourseMapRepository extends JpaRepository<CourseMap, UUID> {
    List<CourseMap> findByMembershipId(UUID membershipId);

    void deleteByMembershipId(UUID membershipId);
}
