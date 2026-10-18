package com.nest.common.security;

import java.util.Set;
import java.util.UUID;

/**
 * The features a membership holds RIGHT NOW. A login token freezes the feature list at the moment it
 * was issued, so a trainer an admin has just granted (or revoked) something would be refused (or
 * still let through) until they signed in again. Where a service can answer from its database it
 * provides this, and {@link FeatureAuthorizationAspect} prefers it over the token.
 */
public interface LiveFeatureLookup {
    Set<String> featuresOf(UUID membershipId);
}
