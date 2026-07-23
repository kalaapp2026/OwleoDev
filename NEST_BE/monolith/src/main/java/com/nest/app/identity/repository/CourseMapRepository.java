package com.nest.app.identity.repository;

import com.nest.app.identity.entity.CourseMap;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface CourseMapRepository extends JpaRepository<CourseMap, UUID> {
    List<CourseMap> findByMembershipId(UUID membershipId);

    List<CourseMap> findByCourseId(UUID courseId);

    Optional<CourseMap> findByMembershipIdAndCourseId(UUID membershipId, UUID courseId);

    void deleteByMembershipId(UUID membershipId);
}
