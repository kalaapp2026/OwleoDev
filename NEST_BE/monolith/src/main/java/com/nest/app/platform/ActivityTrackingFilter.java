package com.nest.app.platform;

import com.nest.app.platform.service.ActivityTracker;
import com.nest.common.security.TenantContext;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

/**
 * Records that the authenticated caller was active. Registered AFTER JwtAuthFilter (see
 * SecurityConfig) because it reads the principal that filter puts in {@link TenantContext} - which
 * is cleared again as soon as JwtAuthFilter's own doFilter returns, so this has to run inside it.
 *
 * <p>Tracking runs after the request is served, so it never adds latency to the response, and any
 * failure inside it is swallowed by {@link ActivityTracker} - a metric must never be able to break
 * a real request.
 */
@Component
public class ActivityTrackingFilter extends OncePerRequestFilter {

    private final ActivityTracker activityTracker;

    public ActivityTrackingFilter(ActivityTracker activityTracker) {
        this.activityTracker = activityTracker;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        try {
            chain.doFilter(request, response);
        } finally {
            UUID userId = TenantContext.currentUserIdOrNull();
            if (userId != null) {
                activityTracker.recordSeen(userId);
            }
        }
    }
}
