package com.nest.app.identity.repository;

import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.common.security.Role;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface AcademyMembershipRepository extends JpaRepository<AcademyMembership, UUID> {
    List<AcademyMembership> findByUserIdAndStatus(UUID userId, MembershipStatus status);

    List<AcademyMembership> findByUserId(UUID userId);

    Optional<AcademyMembership> findByUserIdAndAcademyId(UUID userId, UUID academyId);

    boolean existsByUserIdAndAcademyIdAndStatusNot(UUID userId, UUID academyId, MembershipStatus status);

    /** The batch trainer-picker's "Academy Admin is also a trainer" source - an Admin isn't ever
     * mapped to a course via CourseMap (they have blanket academy access, not per-course
     * enrolment), so they can't be found the same way a Trainer's course_map row is found. */
    List<AcademyMembership> findByAcademyIdAndRoleTypeAndStatus(UUID academyId, Role roleType, MembershipStatus status);
}
