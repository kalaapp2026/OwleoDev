package com.nest.common.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.common.dto.ErrorResponse;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * Gate for {@code /internal/**} paths only - see {@link InternalApiKeyProperties}. A service's
 * SecurityConfig must still explicitly permitAll() these paths in its filter chain (this filter
 * does the actual authorization, JwtAuthFilter is bypassed for them since callers are other
 * services, not end-user sessions).
 */
@Component
public class InternalApiKeyFilter extends OncePerRequestFilter {

    private static final String INTERNAL_PATH_PREFIX = "/internal/";

    private final InternalApiKeyProperties properties;
    private final ObjectMapper objectMapper;

    public InternalApiKeyFilter(InternalApiKeyProperties properties, ObjectMapper objectMapper) {
        this.properties = properties;
        this.objectMapper = objectMapper;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (!request.getRequestURI().startsWith(INTERNAL_PATH_PREFIX)) {
            chain.doFilter(request, response);
            return;
        }

        String provided = request.getHeader(properties.getHeaderName());
        if (provided == null || !provided.equals(properties.getKey())) {
            response.setStatus(HttpStatus.UNAUTHORIZED.value());
            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
            response.getWriter().write(objectMapper.writeValueAsString(ErrorResponse.of(
                    HttpStatus.UNAUTHORIZED.value(), "Unauthorized", "INVALID_INTERNAL_KEY",
                    "Missing or invalid internal service API key", request.getRequestURI())));
            return;
        }

        chain.doFilter(request, response);
    }
}
