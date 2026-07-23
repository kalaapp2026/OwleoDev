package com.nest.app.identity.service;

import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.app.identity.dto.MembershipSummary;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.FeatureGrant;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.FeatureGrantRepository;
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
    private final FeatureGrantRepository featureGrantRepository;
    private final CourseMapRepository courseMapRepository;

    public PrincipalAssembler(AcademyMembershipRepository membershipRepository,
                               FeatureGrantRepository featureGrantRepository,
                               CourseMapRepository courseMapRepository) {
        this.membershipRepository = membershipRepository;
        this.featureGrantRepository = featureGrantRepository;
        this.courseMapRepository = courseMapRepository;
    }

    public NestPrincipal assemble(User user) {
        List<AcademyMembership> activeMemberships =
                membershipRepository.findByUserIdAndStatus(user.getId(), MembershipStatus.ACTIVE);

        List<MembershipClaim> claims = activeMemberships.stream().map(this::toClaim).collect(Collectors.toList());
        UUID activeMembershipId = claims.isEmpty() ? null : claims.get(0).membershipId();

        return new NestPrincipal(user.getId(), user.getUsername(), user.getRole(), claims, activeMembershipId);
    }

    public List<MembershipSummary> summarise(User user) {
        return membershipRepository.findByUserId(user.getId()).stream()
                .map(m -> new MembershipSummary(m.getId(), m.getAcademyId(), m.getAcademyName(), m.getRoleType(),
                        m.getStatus().name(), featureKeysFor(m.getId()), courseIdsFor(m.getId())))
                .collect(Collectors.toList());
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

    private Set<String> featureKeysFor(UUID membershipId) {
        return featureGrantRepository.findByMembershipId(membershipId).stream()
                .map(FeatureGrant::getFeatureKey)
                .collect(Collectors.toSet());
    }

    private Set<UUID> courseIdsFor(UUID membershipId) {
        return courseMapRepository.findByMembershipId(membershipId).stream()
                .map(cm -> cm.getCourseId())
                .collect(Collectors.toSet());
    }
}
