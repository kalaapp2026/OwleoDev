package com.nest.app.identity.service;

import com.nest.common.security.FeatureKey;
import org.junit.jupiter.api.Test;

import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class SchedulingPairTest {

    @Test
    void holdingEitherSchedulingKeyGrantsBoth() {
        assertThat(IdentityRegistrationService.pairScheduling(Set.of(FeatureKey.BATCH_SCHEDULING, FeatureKey.ATTENDANCE)))
                .containsExactlyInAnyOrder(FeatureKey.BATCH_SCHEDULING, FeatureKey.RESCHEDULE, FeatureKey.ATTENDANCE);
        assertThat(IdentityRegistrationService.pairScheduling(Set.of(FeatureKey.RESCHEDULE)))
                .containsExactlyInAnyOrder(FeatureKey.BATCH_SCHEDULING, FeatureKey.RESCHEDULE);
    }

    @Test
    void otherFeaturesAreLeftAlone() {
        Set<String> only = Set.of(FeatureKey.ATTENDANCE, FeatureKey.FEES_ENTRY);
        assertThat(IdentityRegistrationService.pairScheduling(only)).isEqualTo(only);
    }
}
