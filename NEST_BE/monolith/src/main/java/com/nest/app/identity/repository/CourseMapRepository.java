package com.nest.app.identity.repository;

import com.nest.app.identity.entity.CourseMap;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface CourseMapRepository extends JpaRepository<CourseMap, UUID> {
    List<CourseMap> findByMembershipId(UUID membershipId);

    List<CourseMap> findByCourseId(UUID courseId);

    Optional<CourseMap> findByMembershipIdAndCourseId(UUID membershipId, UUID courseId);

    // Bulk delete, not derived load-then-remove - see CourseFeatureGrantRepository's
    // deleteByMembershipId for why (Hibernate flushes inserts before deletes, so a
    // delete-then-reinsert of an unchanged row in one transaction needs the delete to actually
    // hit the database immediately, not just get queued).
    @Modifying(clearAutomatically = true)
    @Query("delete from CourseMap c where c.membershipId = :membershipId")
    void deleteByMembershipId(@Param("membershipId") UUID membershipId);
}
