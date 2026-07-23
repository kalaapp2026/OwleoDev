package com.nest.common.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.common.dto.ErrorResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;

import java.io.IOException;

/**
 * Without this, Spring Security's default for a stateless API (no formLogin/httpBasic
 * configured) is {@code Http403ForbiddenEntryPoint} - a bare 403 with no body, for BOTH "no
 * token at all" and "token present but insufficient rights". That collapses two different
 * problems into one status code and breaks the consistent {@link ErrorResponse} shape every
 * other error path uses. This restores the 401-for-missing-credentials / 403-for-insufficient-
 * rights distinction.
 */
@Component
public class NestAuthenticationEntryPoint implements AuthenticationEntryPoint {

    private final ObjectMapper objectMapper;

    public NestAuthenticationEntryPoint(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response, AuthenticationException authException)
            throws IOException {
        response.setStatus(HttpStatus.UNAUTHORIZED.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        ErrorResponse body = ErrorResponse.of(HttpStatus.UNAUTHORIZED.value(), "Unauthorized", "UNAUTHORIZED",
                "Authentication is required to access this resource", request.getRequestURI());
        response.getWriter().write(objectMapper.writeValueAsString(body));
    }
}
