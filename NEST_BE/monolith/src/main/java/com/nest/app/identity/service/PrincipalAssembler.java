package com.nest.app.identity.service;

import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.app.academy.entity.AcademyStatus;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.identity.dto.MembershipSummary;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.CourseFeatureGrant;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseFeatureGrantRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Builds the JWT-carried {@link NestPrincipal} (and its Flutter-facing {@link MembershipSummary}
 * equivalent) from a user's currently ACTIVE memberships, each with its feature_grants and
 * course_map. This is the one place that assembles the claim shape described in PRD 4.3, so
 * login, refresh and /users/me all stay consistent.
 */
@Component
public class PrincipalAssembler {

    private final AcademyMembershipRepository membershipRepository;
    private final CourseFeatureGrantRepository courseFeatureGrantRepository;
    private final CourseMapRepository courseMapRepository;
    private final AcademyRepository academyRepository;

    public PrincipalAssembler(AcademyMembershipRepository membershipRepository,
                               CourseFeatureGrantRepository courseFeatureGrantRepository,
                               CourseMapRepository courseMapRepository,
                               AcademyRepository academyRepository) {
        this.membershipRepository = membershipRepository;
        this.courseFeatureGrantRepository = courseFeatureGrantRepository;
        this.courseMapRepository = courseMapRepository;
        this.academyRepository = academyRepository;
    }

    public NestPrincipal assemble(User user) {
        List<AcademyMembership> activeMemberships =
                membershipRepository.findByUserIdAndStatus(user.getId(), MembershipStatus.ACTIVE).stream()
                        .filter(m -> !isAcademySuspended(m.getAcademyId()))
                        .collect(Collectors.toList());

        List<MembershipClaim> claims = activeMemberships.stream().map(this::toClaim).collect(Collectors.toList());
        UUID activeMembershipId = claims.isEmpty() ? null : claims.get(0).membershipId();

        return new NestPrincipal(user.getId(), user.getUsername(), user.getRole(), claims, activeMembershipId);
    }

    public List<MembershipSummary> summarise(User user) {
        // Same suspension filter as assemble() - a suspended academy vanishes from the switcher and
        // the membership list, not just from feature/course grants (PRD 2.4 tenant suspension).
        return membershipRepository.findByUserId(user.getId()).stream()
                .filter(m -> !isAcademySuspended(m.getAcademyId()))
                .map(m -> new MembershipSummary(m.getId(), m.getAcademyId(), m.getAcademyName(), m.getRoleType(),
                        m.getStatus().name(), featureKeysFor(m.getId()), courseIdsFor(m.getId())))
                .collect(Collectors.toList());
    }

    private boolean isAcademySuspended(UUID academyId) {
        return academyRepository.findById(academyId)
                .map(a -> a.getStatus() == AcademyStatus.SUSPENDED)
                .orElse(false);
    }

    private MembershipClaim toClaim(AcademyMembership membership) {
        return new MembershipClaim(
                membership.getId(),
                membership.getAcademyId(),
                membership.getAcademyName(),
                membership.getRoleType(),
                featureKeysFor(membership.getId()),
                courseIdsFor(membership.getId())
        );
    }

    /** The UNION of a trainer's per-course features - what the coarse @RequiresFeature gate checks
     * ("do they have this feature on any course?"). Per-course enforcement (Phase 2) checks the
     * specific course instead. */
    private Set<String> featureKeysFor(UUID membershipId) {
        return courseFeatureGrantRepository.findByMembershipId(membershipId).stream()
                .map(CourseFeatureGrant::getFeatureKey)
                .collect(Collectors.toSet());
    }

    private Set<UUID> courseIdsFor(UUID membershipId) {
        // Only ACTIVE course maps - a course the admin deactivated this person from must not appear
        // in their JWT courseIds, or @RequiresCourseAccess-style gates would still let them in.
        return courseMapRepository.findByMembershipId(membershipId).stream()
                .filter(CourseMap::isActive)
                .map(CourseMap::getCourseId)
                .collect(Collectors.toSet());
    }
}
