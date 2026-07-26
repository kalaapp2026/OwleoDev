package com.nest.app.identity.service;

import com.nest.app.identity.repository.CourseFeatureGrantRepository;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

/** The crux of "truly enforced per-course": a Trainer is checked against THIS course's grants;
 * Admins/Super Admins bypass entirely (same as the coarse @RequiresFeature aspect). */
@ExtendWith(MockitoExtension.class)
class CourseFeatureGuardTest {

    @Mock
    private CourseFeatureGrantRepository repo;

    private CourseFeatureGuard guard;

    private final UUID guitar = UUID.randomUUID();
    private final UUID dance = UUID.randomUUID();

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private UUID actingAsTrainer() {
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Natyalaya", Role.TRAINER, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "ravi", Role.TRAINER, List.of(claim), membershipId));
        return membershipId;
    }

    @Test
    void trainerWithTheFeatureOnThisCoursePasses() {
        guard = new CourseFeatureGuard(repo);
        UUID membershipId = actingAsTrainer();
        when(repo.existsByMembershipIdAndCourseIdAndFeatureKey(membershipId, guitar, FeatureKey.ATTENDANCE)).thenReturn(true);

        assertThatCode(() -> guard.assertCourseFeature(guitar, FeatureKey.ATTENDANCE)).doesNotThrowAnyException();
    }

    @Test
    void trainerWithTheFeatureOnlyOnAnotherCourseIsBlocked() {
        guard = new CourseFeatureGuard(repo);
        UUID membershipId = actingAsTrainer();
        // Has Attendance on Guitar, asks to act on Dance - the per-course check says no.
        when(repo.existsByMembershipIdAndCourseIdAndFeatureKey(membershipId, dance, FeatureKey.ATTENDANCE)).thenReturn(false);

        assertThatThrownBy(() -> guard.assertCourseFeature(dance, FeatureKey.ATTENDANCE))
                .isInstanceOf(ForbiddenException.class);
    }

    @Test
    void academyAdminBypassesTheCourseCheckEntirely() {
        guard = new CourseFeatureGuard(repo);
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN, List.of(claim), membershipId));
        lenient().when(repo.existsByMembershipIdAndCourseIdAndFeatureKey(membershipId, dance, FeatureKey.ATTENDANCE)).thenReturn(false);

        assertThatCode(() -> guard.assertCourseFeature(dance, FeatureKey.ATTENDANCE)).doesNotThrowAnyException();
    }
}
