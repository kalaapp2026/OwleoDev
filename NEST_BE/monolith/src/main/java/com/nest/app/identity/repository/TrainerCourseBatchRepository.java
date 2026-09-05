package com.nest.app.identity.repository;

import com.nest.app.identity.entity.TrainerCourseBatch;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface TrainerCourseBatchRepository
        extends JpaRepository<TrainerCourseBatch, TrainerCourseBatch.Key> {

    List<TrainerCourseBatch> findByMembershipId(UUID membershipId);

    /**
     * Bulk delete rather than a derived deleteBy: the derived form loads each row and queues a
     * remove, and Hibernate flushes INSERTs before DELETEs regardless of call order - so a
     * caller that replaces a trainer's mappings in one transaction hits the primary key on an
     * unchanged row before the delete ever reaches the database. Same reasoning as
     * CourseFeatureGrantRepository.deleteByMembershipId.
     */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("delete from TrainerCourseBatch t where t.membershipId = :membershipId")
    void deleteByMembershipId(@Param("membershipId") UUID membershipId);
}
