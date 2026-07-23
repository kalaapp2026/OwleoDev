package com.nest.common.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * MVP placeholder for service-to-service auth on {@code /internal/**} endpoints (e.g.
 * academy-service calling identity-service to provision an Academy Admin). Harden this to
 * mTLS or OAuth2 client-credentials before production - a shared static key is not a long-term
 * answer, just a working stand-in so Phase 1 cross-service calls can be built and tested now.
 */
@ConfigurationProperties(prefix = "nest.internal-api")
public class InternalApiKeyProperties {

    private String key = "dev-only-internal-key-change-me";
    private String headerName = "X-Internal-Api-Key";

    public String getKey() {
        return key;
    }

    public void setKey(String key) {
        this.key = key;
    }

    public String getHeaderName() {
        return headerName;
    }

    public void setHeaderName(String headerName) {
        this.headerName = headerName;
    }
}
