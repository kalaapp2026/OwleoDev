package com.nest.app.identity.service;

import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.FeatureAuthorizationAspect;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.LiveFeatureLookup;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.RequiresFeature;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.aspectj.lang.ProceedingJoinPoint;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/** The coarse feature gate reads the trainer's grants as stored now, not as frozen in the login token. */
class LiveFeatureGateTest {

    @RequiresFeature({FeatureKey.BATCH_CREATION, FeatureKey.STUDENT_REGISTRATION})
    void gated() {
    }

    private final UUID membershipId = UUID.randomUUID();

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private Object run(Set<String> tokenFeatures, Set<String> liveFeatures) throws Throwable {
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Academy", Role.TRAINER,
                tokenFeatures, Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "nandi", Role.TRAINER, List.of(claim), membershipId));
        @SuppressWarnings("unchecked")
        ObjectProvider<LiveFeatureLookup> provider = mock(ObjectProvider.class);
        LiveFeatureLookup lookup = mock(LiveFeatureLookup.class);
        when(lookup.featuresOf(membershipId)).thenReturn(liveFeatures);
        when(provider.getIfAvailable()).thenReturn(lookup);
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        when(pjp.proceed()).thenReturn("ok");
        RequiresFeature rf = LiveFeatureGateTest.class.getDeclaredMethod("gated").getAnnotation(RequiresFeature.class);
        return new FeatureAuthorizationAspect(provider).enforce(pjp, rf);
    }

    @Test
    void aFeatureGrantedAfterLoginPassesWithoutANewToken() throws Throwable {
        assertThat(run(Set.of(FeatureKey.ATTENDANCE), Set.of(FeatureKey.ATTENDANCE, FeatureKey.BATCH_CREATION)))
                .isEqualTo("ok");
    }

    @Test
    void aFeatureRevokedAfterLoginIsRefusedEvenThoughTheTokenStillCarriesIt() {
        assertThatThrownBy(() -> run(Set.of(FeatureKey.BATCH_CREATION), Set.of(FeatureKey.ATTENDANCE)))
                .isInstanceOf(ForbiddenException.class);
    }
}
