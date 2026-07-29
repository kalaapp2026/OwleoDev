package com.nest.app.curriculum.repository;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.CourseStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface CourseRepository extends JpaRepository<Course, UUID> {
    List<Course> findByAcademyIdAndStatus(UUID academyId, CourseStatus status);

    List<Course> findByAcademyId(UUID academyId);

    /** Scheduled fee-slip generation's entry point - runs with no TenantContext (background
     * thread, not an HTTP request), so it must find every academy's due courses in one query
     * rather than going through the usual "active academy" scoping used everywhere else. */
    List<Course> findByBillingDayOfMonthAndStatus(Integer billingDayOfMonth, CourseStatus status);

    // ---- Super Admin platform metrics ----

    long countByStatus(CourseStatus status);

    long countByAcademyIdAndStatus(UUID academyId, CourseStatus status);

    /** Batch counts per academy have to go through courses - Batch has no academy_id of its own. */
    @Query("select c.id from Course c where c.academyId = :academyId")
    List<UUID> findIdsByAcademyId(@Param("academyId") UUID academyId);

    /** Course counts for every academy at once - see AcademyMembershipRepository.countByAcademyAndRole
     * for why these are grouped rather than asked per academy. */
    @Query("select c.academyId, count(c) from Course c where c.status = :status group by c.academyId")
    List<Object[]> countByAcademyGrouped(@Param("status") CourseStatus status);
}
