package com.nest.app.enrolment.repository;

import com.nest.app.enrolment.entity.Batch;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

public interface BatchRepository extends JpaRepository<Batch, UUID> {
    /** Every batch that covers {@code courseId} - as its primary course OR as one of the several it spans.
     * A batch of Basic + Intermediate + Advanced learners therefore shows under all three courses. */
    @Query("select distinct b from Batch b where b.courseId = :courseId or :courseId member of b.courseIds")
    List<Batch> findByCourseId(@Param("courseId") UUID courseId);

    /** Calendar's "every batch in this academy" source for an Academy Admin, joined through the
     * courses they own - Batch has no academy_id column of its own. A batch is returned once even when
     * it covers several of {@code courseIds}. */
    @Query("select distinct b from Batch b left join b.courseIds ec where b.courseId in :courseIds or ec in :courseIds")
    List<Batch> findByCourseIdIn(@Param("courseIds") Collection<UUID> courseIds);

    /** Calendar's source for a Trainer's own classes - the batches they're the default trainer for. */
    List<Batch> findByTrainerMembershipId(UUID trainerMembershipId);

    /** Batch counts for every academy at once. Batch has no academy_id, so this joins through
     * Course - written as a cross-join with an explicit id match because the two entities have no
     * mapped JPA association (courseId is a plain UUID column). */
    @Query("""
            select c.academyId, count(b)
            from Batch b, Course c
            where b.courseId = c.id
            group by c.academyId
            """)
    List<Object[]> countByAcademyGrouped();
}
