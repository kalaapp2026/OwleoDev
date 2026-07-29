package com.nest.app.enrolment.repository;

import com.nest.app.enrolment.entity.Batch;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

public interface BatchRepository extends JpaRepository<Batch, UUID> {
    List<Batch> findByCourseId(UUID courseId);

    /** Calendar's "every batch in this academy" source for an Academy Admin, joined through the
     * courses they own - Batch has no academy_id column of its own. */
    List<Batch> findByCourseIdIn(Collection<UUID> courseIds);

    /** Calendar's source for a Trainer's own classes - the batches they're the default trainer for. */
    List<Batch> findByTrainerMembershipId(UUID trainerMembershipId);

    /** Super Admin platform metrics - per-academy batch count, via that academy's course ids. */
    long countByCourseIdIn(Collection<UUID> courseIds);

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
