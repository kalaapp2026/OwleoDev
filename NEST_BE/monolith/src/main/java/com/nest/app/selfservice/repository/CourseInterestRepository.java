package com.nest.app.selfservice.repository;

import com.nest.app.selfservice.entity.CourseInterest;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface CourseInterestRepository extends JpaRepository<CourseInterest, UUID> {
    List<CourseInterest> findByMembershipId(UUID membershipId);

    boolean existsByCourseIdAndMembershipId(UUID courseId, UUID membershipId);

    void deleteByCourseIdAndMembershipId(UUID courseId, UUID membershipId);
}
