package com.nest.gateway.config;

import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import reactor.core.publisher.Mono;

/**
 * IP-based key for the Redis rate limiter (PRD 4.2 gateway responsibility: "rate limiting").
 * Phase 1 does not re-validate the JWT at the gateway (each service already does so via
 * JwtAuthFilter - defense in depth per PRD 4.3), so per-user rate limiting isn't available here
 * yet; revisit once the gateway parses claims itself.
 */
@Configuration
public class RateLimiterConfig {

    @Bean
    public KeyResolver ipKeyResolver() {
        return exchange -> Mono.justOrEmpty(exchange.getRequest().getRemoteAddress())
                .map(addr -> addr.getAddress().getHostAddress())
                .defaultIfEmpty("unknown");
    }
}
