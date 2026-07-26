package com.nest.app.identity.repository;

import com.nest.app.identity.entity.CourseFeatureGrant;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface CourseFeatureGrantRepository extends JpaRepository<CourseFeatureGrant, UUID> {
    List<CourseFeatureGrant> findByMembershipId(UUID membershipId);

    // A derived void deleteByMembershipId() loads each row then calls entityManager.remove() on
    // it, which just queues an EntityDeleteAction - Hibernate's flush always runs INSERT actions
    // before DELETE actions regardless of call order, so a caller that deletes-then-reinserts an
    // UNCHANGED (membership, course, feature) row in the same transaction hits this row's own
    // unique constraint before the delete ever reaches the database. A bulk @Modifying query
    // executes immediately as a real SQL DELETE, so it's guaranteed to happen before any insert
    // that runs later in the same method.
    @Modifying(clearAutomatically = true)
    @Query("delete from CourseFeatureGrant g where g.membershipId = :membershipId")
    void deleteByMembershipId(@Param("membershipId") UUID membershipId);

    /** The per-course enforcement check: does this trainer hold this feature on this exact course? */
    boolean existsByMembershipIdAndCourseIdAndFeatureKey(UUID membershipId, UUID courseId, String featureKey);
}
