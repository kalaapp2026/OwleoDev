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

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

/** The crux of "truly enforced per-course": a Trainer is checked against THIS course's grants;
 * Admins/Super Admins bypass entirely (same as the coarse @RequiresFeature aspect). */
@ExtendWith(MockitoExtension.class)
class CourseFeatureGuardTest {

    @Mock
    private CourseFeatureGrantRepository repo;
    @Mock
    private com.nest.app.identity.repository.TrainerCourseBatchRepository batchRepo;

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
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = actingAsTrainer();
        when(repo.existsByMembershipIdAndCourseIdAndFeatureKey(membershipId, guitar, FeatureKey.ATTENDANCE)).thenReturn(true);

        assertThatCode(() -> guard.assertCourseFeature(guitar, FeatureKey.ATTENDANCE)).doesNotThrowAnyException();
    }

    @Test
    void trainerWithTheFeatureOnlyOnAnotherCourseIsBlocked() {
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = actingAsTrainer();
        // Has Attendance on Guitar, asks to act on Dance - the per-course check says no.
        when(repo.existsByMembershipIdAndCourseIdAndFeatureKey(membershipId, dance, FeatureKey.ATTENDANCE)).thenReturn(false);

        assertThatThrownBy(() -> guard.assertCourseFeature(dance, FeatureKey.ATTENDANCE))
                .isInstanceOf(ForbiddenException.class);
    }

    @Test
    void academyAdminBypassesTheCourseCheckEntirely() {
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN, List.of(claim), membershipId));
        lenient().when(repo.existsByMembershipIdAndCourseIdAndFeatureKey(membershipId, dance, FeatureKey.ATTENDANCE)).thenReturn(false);

        assertThatCode(() -> guard.assertCourseFeature(dance, FeatureKey.ATTENDANCE)).doesNotThrowAnyException();
    }

    // ------------------------------------------------------------------
    // visibleCourseIds - what belongs on a caller's SCREEN, as opposed to
    // assertCourseFeature, which is what they may WRITE to.
    // ------------------------------------------------------------------

    private com.nest.app.identity.entity.CourseFeatureGrant grant(UUID membershipId, UUID courseId, String feature) {
        return com.nest.app.identity.entity.CourseFeatureGrant.builder()
                .id(UUID.randomUUID()).membershipId(membershipId).courseId(courseId).featureKey(feature).build();
    }

    @Test
    void aTrainerSeesOnlyTheCoursesTheyHoldTheFeatureOn() {
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = actingAsTrainer();
        when(repo.findByMembershipId(membershipId)).thenReturn(List.of(
                grant(membershipId, guitar, FeatureKey.ATTENDANCE),
                // A grant on a different feature must not widen what they see for this one.
                grant(membershipId, dance, FeatureKey.FEES_ENTRY)));

        var visible = guard.visibleCourseIds(FeatureKey.ATTENDANCE);

        assertThat(visible).isPresent();
        assertThat(visible.get()).containsExactly(guitar);
    }

    @Test
    void aTrainerWithNoGrantForTheFeatureSeesNothing() {
        // The dangerous failure mode: an empty grant list must mean an empty screen, never an
        // unrestricted one.
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = actingAsTrainer();
        when(repo.findByMembershipId(membershipId)).thenReturn(List.of());

        var visible = guard.visibleCourseIds(FeatureKey.ATTENDANCE);

        assertThat(visible).isPresent();
        assertThat(visible.get()).isEmpty();
    }

    @Test
    void anAdminIsUnrestrictedRatherThanGivenAnExplicitList() {
        // Empty Optional means "no filter" - distinct from an empty Set, which means "nothing".
        // Conflating the two is precisely how this leaks or blanks.
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN, List.of(claim), membershipId));

        assertThat(guard.visibleCourseIds(FeatureKey.ATTENDANCE)).isEmpty();
    }

    // ---------------------------------------------------------------- any-of

    @Test
    void holdingEitherOfTwoFeaturesOnTheCoursePassesAnAnyOfCheck() {
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = actingAsTrainer();
        when(repo.existsByMembershipIdAndCourseIdAndFeatureKey(membershipId, guitar, FeatureKey.BATCH_CREATION)).thenReturn(false);
        when(repo.existsByMembershipIdAndCourseIdAndFeatureKey(membershipId, guitar, FeatureKey.STUDENT_REGISTRATION)).thenReturn(true);

        assertThatCode(() -> guard.assertAnyCourseFeature(guitar, FeatureKey.BATCH_CREATION, FeatureKey.STUDENT_REGISTRATION))
                .doesNotThrowAnyException();
    }

    @Test
    void holdingNeitherFailsAnAnyOfCheck() {
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = actingAsTrainer();
        when(repo.existsByMembershipIdAndCourseIdAndFeatureKey(any(), any(), any())).thenReturn(false);

        assertThatThrownBy(() -> guard.assertAnyCourseFeature(guitar, FeatureKey.BATCH_CREATION, FeatureKey.STUDENT_REGISTRATION))
                .isInstanceOf(ForbiddenException.class);
    }

    @Test
    void theVisibleCoursesForSeveralFeaturesAreTheirUnion() {
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = actingAsTrainer();
        when(repo.findByMembershipId(membershipId)).thenReturn(List.of(
                com.nest.app.identity.entity.CourseFeatureGrant.builder().membershipId(membershipId).courseId(guitar).featureKey(FeatureKey.RESCHEDULE).build(),
                com.nest.app.identity.entity.CourseFeatureGrant.builder().membershipId(membershipId).courseId(dance).featureKey(FeatureKey.BATCH_SCHEDULING).build(),
                com.nest.app.identity.entity.CourseFeatureGrant.builder().membershipId(membershipId).courseId(UUID.randomUUID()).featureKey(FeatureKey.FEES_ENTRY).build()));

        var visible = guard.visibleCourseIdsAny(FeatureKey.RESCHEDULE, FeatureKey.BATCH_SCHEDULING);

        assertThat(visible).isPresent();
        assertThat(visible.get()).containsExactlyInAnyOrder(guitar, dance);
    }

    // ------------------------------------------------------------ batch scope

    @Test
    void aTrainerGivenNoSpecificBatchesIsNotLimited() {
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = actingAsTrainer();
        when(batchRepo.findByMembershipIdAndCourseId(membershipId, guitar)).thenReturn(List.of());

        assertThat(guard.batchScope(guitar)).isEmpty();
    }

    @Test
    void aTrainerGivenSomeBatchesIsLimitedToThem() {
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = actingAsTrainer();
        UUID batchA = UUID.randomUUID();
        UUID batchB = UUID.randomUUID();
        when(batchRepo.findByMembershipIdAndCourseId(membershipId, guitar)).thenReturn(List.of(
                com.nest.app.identity.entity.TrainerCourseBatch.builder().membershipId(membershipId).courseId(guitar).batchId(batchA).build()));

        assertThat(guard.batchScope(guitar)).contains(java.util.Set.of(batchA));
        assertThatCode(() -> guard.assertBatchInScope(guitar, batchA)).doesNotThrowAnyException();
        assertThatThrownBy(() -> guard.assertBatchInScope(guitar, batchB)).isInstanceOf(ForbiddenException.class);
    }

    @Test
    void anAdminIsNeverLimitedToBatches() {
        guard = new CourseFeatureGuard(repo, batchRepo);
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN, List.of(claim), membershipId));

        assertThat(guard.batchScope(guitar)).isEmpty();
        assertThatCode(() -> guard.assertBatchInScope(guitar, UUID.randomUUID())).doesNotThrowAnyException();
    }
}
