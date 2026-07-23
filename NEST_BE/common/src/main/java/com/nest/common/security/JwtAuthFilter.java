package com.nest.common.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.common.dto.ErrorResponse;
import com.nest.common.exception.UnauthorizedException;
import io.jsonwebtoken.Claims;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;
import java.util.UUID;

/**
 * Populates {@link TenantContext} and the Spring SecurityContext from the JWT access token on
 * every request. Also honours an optional {@code X-Active-Membership} header, which is how the
 * Flutter Academy Switcher (PRD 3.1.1) tells the backend which of the caller's memberships is in
 * view for this particular screen/request - the token itself may carry several.
 */
@Component
public class JwtAuthFilter extends OncePerRequestFilter {

    private static final String BEARER_PREFIX = "Bearer ";
    private static final String ACTIVE_MEMBERSHIP_HEADER = "X-Active-Membership";

    private final JwtTokenProvider tokenProvider;
    private final ObjectMapper objectMapper;

    public JwtAuthFilter(JwtTokenProvider tokenProvider, ObjectMapper objectMapper) {
        this.tokenProvider = tokenProvider;
        this.objectMapper = objectMapper;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header == null || !header.startsWith(BEARER_PREFIX)) {
            chain.doFilter(request, response);
            return;
        }

        try {
            String token = header.substring(BEARER_PREFIX.length());
            Claims claims = tokenProvider.parse(token);
            if (tokenProvider.isRefreshToken(claims)) {
                throw new UnauthorizedException("Refresh token cannot be used as an access token");
            }
            NestPrincipal principal = tokenProvider.toPrincipal(claims);
            principal = applyActiveMembershipOverride(principal, request.getHeader(ACTIVE_MEMBERSHIP_HEADER));

            TenantContext.set(principal);

            List<GrantedAuthority> authorities = List.of(new SimpleGrantedAuthority("ROLE_" + principal.globalRole().name()));
            var authentication = new UsernamePasswordAuthenticationToken(principal, null, authorities);
            authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
            SecurityContextHolder.getContext().setAuthentication(authentication);

            chain.doFilter(request, response);
        } catch (UnauthorizedException ex) {
            writeUnauthorized(response, ex.getMessage(), request.getRequestURI());
        } finally {
            TenantContext.clear();
        }
    }

    private NestPrincipal applyActiveMembershipOverride(NestPrincipal principal, String headerValue) {
        if (headerValue == null || headerValue.isBlank()) {
            return principal;
        }
        UUID requested;
        try {
            requested = UUID.fromString(headerValue);
        } catch (IllegalArgumentException ex) {
            throw new UnauthorizedException("X-Active-Membership header is not a valid membership id");
        }
        if (!principal.hasMembership(requested)) {
            throw new UnauthorizedException("Requested active membership is not one of the caller's memberships");
        }
        return new NestPrincipal(principal.userId(), principal.username(), principal.globalRole(),
                principal.memberships(), requested);
    }

    private void writeUnauthorized(HttpServletResponse response, String message, String path) throws IOException {
        response.setStatus(HttpStatus.UNAUTHORIZED.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        ErrorResponse body = ErrorResponse.of(HttpStatus.UNAUTHORIZED.value(), "Unauthorized", "UNAUTHORIZED", message, path);
        response.getWriter().write(objectMapper.writeValueAsString(body));
    }
}
