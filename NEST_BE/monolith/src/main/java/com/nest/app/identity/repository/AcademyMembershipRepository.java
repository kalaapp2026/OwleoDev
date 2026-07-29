package com.nest.app.identity.repository;

import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.common.security.Role;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface AcademyMembershipRepository extends JpaRepository<AcademyMembership, UUID> {
    List<AcademyMembership> findByUserIdAndStatus(UUID userId, MembershipStatus status);

    List<AcademyMembership> findByUserId(UUID userId);

    Optional<AcademyMembership> findByUserIdAndAcademyId(UUID userId, UUID academyId);

    /** Every membership in an academy - the Super Admin broadcast console's "notify one academy"
     * audience resolves to the distinct user ids behind these rows. */
    List<AcademyMembership> findByAcademyId(UUID academyId);

    boolean existsByUserIdAndAcademyIdAndStatusNot(UUID userId, UUID academyId, MembershipStatus status);

    /** The batch trainer-picker's "Academy Admin is also a trainer" source - an Admin isn't ever
     * mapped to a course via CourseMap (they have blanket academy access, not per-course
     * enrolment), so they can't be found the same way a Trainer's course_map row is found. */
    List<AcademyMembership> findByAcademyIdAndRoleTypeAndStatus(UUID academyId, Role roleType, MembershipStatus status);

    // ---- Super Admin platform metrics ----

    /** Per-academy headcount by role. Counts MEMBERSHIPS, not people: the same person teaching at
     * two academies is one user but two trainers, which is the right unit for "how big is this
     * academy". Platform-wide user totals come from UserRepository instead. */
    long countByAcademyIdAndRoleTypeAndStatus(UUID academyId, Role roleType, MembershipStatus status);

    long countByRoleTypeAndStatus(Role roleType, MembershipStatus status);

    /**
     * Headcount for EVERY academy at once, as (academyId, roleType, count) rows. Grouped on
     * purpose: the Super Admin academy list needs this for every tenant, and asking per-academy
     * would be one query per academy per role.
     */
    @Query("""
            select m.academyId, m.roleType, count(m)
            from AcademyMembership m
            where m.status = :status
            group by m.academyId, m.roleType
            """)
    List<Object[]> countByAcademyAndRole(@Param("status") MembershipStatus status);

    /** Most recent sign of life in each academy - the newest last_seen_at across its members.
     * Answers "is this tenant actually being used" without opening it. */
    @Query("""
            select m.academyId, max(u.lastSeenAt)
            from AcademyMembership m, User u
            where m.userId = u.id and m.status = :status
            group by m.academyId
            """)
    List<Object[]> lastActivityByAcademy(@Param("status") MembershipStatus status);
}
