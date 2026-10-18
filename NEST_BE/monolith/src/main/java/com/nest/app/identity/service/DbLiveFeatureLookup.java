package com.nest.app.identity.service;

import com.nest.app.identity.entity.CourseFeatureGrant;
import com.nest.app.identity.repository.CourseFeatureGrantRepository;
import com.nest.common.security.LiveFeatureLookup;
import org.springframework.stereotype.Component;

import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/** A membership's features as stored now - the union over its courses, as {@link PrincipalAssembler}
 * puts in a token, but read at request time so a grant takes effect without a fresh login. */
@Component
public class DbLiveFeatureLookup implements LiveFeatureLookup {

    private final CourseFeatureGrantRepository grants;

    public DbLiveFeatureLookup(CourseFeatureGrantRepository grants) {
        this.grants = grants;
    }

    @Override
    public Set<String> featuresOf(UUID membershipId) {
        return grants.findByMembershipId(membershipId).stream()
                .map(CourseFeatureGrant::getFeatureKey)
                .collect(Collectors.toSet());
    }
}
