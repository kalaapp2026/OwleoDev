package com.nest.common.security;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Covers the worked example in PRD 2.3: Arjun is granted {ATTENDANCE, BATCH_SCHEDULING,
 * RESCHEDULE} and mapped to {Bharatanatyam, Guitar} only - he must pass feature+course checks for
 * his own grants and fail for anything outside them, and switching his active membership must not
 * leak another academy's grants.
 */
class NestPrincipalRbacTest {

    private final UUID bharatanatyamCourseId = UUID.randomUUID();
    private final UUID tablaCourseId = UUID.randomUUID();
    private final UUID natyalayaMembershipId = UUID.randomUUID();
    private final UUID otherAcademyMembershipId = UUID.randomUUID();

    private NestPrincipal arjun() {
        MembershipClaim natyalaya = new MembershipClaim(
                natyalayaMembershipId, UUID.randomUUID(), "Natyalaya",
                Role.TRAINER,
                Set.of(FeatureKey.ATTENDANCE, FeatureKey.BATCH_SCHEDULING, FeatureKey.RESCHEDULE),
                Set.of(bharatanatyamCourseId)
        );
        MembershipClaim elsewhere = new MembershipClaim(
                otherAcademyMembershipId, UUID.randomUUID(), "Some Other Academy",
                Role.STUDENT,
                Set.of(),
                Set.of()
        );
        return new NestPrincipal(UUID.randomUUID(), "arjun", Role.TRAINER,
                List.of(natyalaya, elsewhere), natyalayaMembershipId);
    }

    @Test
    void grantedFeatureOnActiveMembershipIsAllowed() {
        assertThat(arjun().hasFeature(FeatureKey.ATTENDANCE)).isTrue();
    }

    @Test
    void ungrantedFeatureIsDenied() {
        NestPrincipal arjun = arjun();
        assertThat(arjun.hasFeature(FeatureKey.FEES_DASHBOARD)).isFalse();
        assertThat(arjun.hasFeature(FeatureKey.STUDENT_REGISTRATION)).isFalse();
    }

    @Test
    void mappedCourseIsAccessible() {
        assertThat(arjun().hasCourse(bharatanatyamCourseId)).isTrue();
    }

    @Test
    void unmappedCourseInSameAcademyIsInvisible() {
        // Tabla exists in the same academy but Arjun was never mapped to it (PRD 2.3 example).
        assertThat(arjun().hasCourse(tablaCourseId)).isFalse();
    }

    @Test
    void switchingActiveMembershipChangesEffectiveGrants() {
        NestPrincipal arjun = arjun();
        NestPrincipal switched = new NestPrincipal(arjun.userId(), arjun.username(), arjun.globalRole(),
                arjun.memberships(), otherAcademyMembershipId);

        assertThat(switched.hasFeature(FeatureKey.ATTENDANCE))
                .as("grants from the Natyalaya membership must not leak once a different membership is active")
                .isFalse();
    }

    @Test
    void superAdminHasNoMembershipsButIsIdentifiedGlobally() {
        NestPrincipal superAdmin = new NestPrincipal(UUID.randomUUID(), "platform_owner", Role.SUPER_ADMIN, List.of(), null);
        assertThat(superAdmin.isSuperAdmin()).isTrue();
        assertThat(superAdmin.activeMembership()).isEmpty();
    }
}
