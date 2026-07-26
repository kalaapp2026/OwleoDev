package com.nest.app.identity.repository;

import com.nest.app.identity.entity.CourseFeatureGrant;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface CourseFeatureGrantRepository extends JpaRepository<CourseFeatureGrant, UUID> {
    List<CourseFeatureGrant> findByMembershipId(UUID membershipId);

    void deleteByMembershipId(UUID membershipId);

    /** The per-course enforcement check: does this trainer hold this feature on this exact course? */
    boolean existsByMembershipIdAndCourseIdAndFeatureKey(UUID membershipId, UUID courseId, String featureKey);
}
