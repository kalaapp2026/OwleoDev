package com.nest.app.enrolment.repository;

import com.nest.app.enrolment.entity.StudentCourseChange;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public interface StudentCourseChangeRepository extends JpaRepository<StudentCourseChange, UUID> {

    List<StudentCourseChange> findByMembershipIdAndStatusOrderByEffectiveOnAsc(
            UUID membershipId, StudentCourseChange.Status status);

    /** Everything due on or before {@code date} that has not been applied - the job's worklist. */
    List<StudentCourseChange> findByStatusAndEffectiveOnLessThanEqual(
            StudentCourseChange.Status status, LocalDate date);

    boolean existsByMembershipIdAndFromCourseIdAndStatus(
            UUID membershipId, UUID fromCourseId, StudentCourseChange.Status status);
}
