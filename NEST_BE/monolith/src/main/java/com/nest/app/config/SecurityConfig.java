package com.nest.app.config;

import com.nest.app.platform.ActivityTrackingFilter;
import com.nest.common.security.JwtAuthFilter;
import com.nest.common.security.NestAuthenticationEntryPoint;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;
import java.util.List;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    private static final String[] PUBLIC_PATHS = {
            "/auth/**",
            // Install counting has to work BEFORE login - an install that never signs up is still
            // an install. Carries no PII (client-generated device id only) and is idempotent.
            "/devices/ping",
            "/swagger-ui/**", "/v3/api-docs/**", "/v3/api-docs.yaml",
            "/actuator/health",
            // Uploaded avatars - just images, not sensitive documents, so an <img src> doesn't
            // need to carry an Authorization header (see WebConfig).
            "/uploads/**"
    };

    /** The Flutter web build runs on its own origin (localhost:5000 in dev, a real domain once
     * deployed) - without CORS the browser blocks every request before it even reaches
     * JwtAuthFilter, regardless of how correct the backend logic is.
     *
     * <p>The default below is DEV ONLY. A deployed web build is served from its own https origin,
     * which is not in this list, so every API call from it fails at the browser until the host's
     * environment sets the origin explicitly. The env var is
     * {@code NEST_CORS_ALLOWED_ORIGINS} (Spring's relaxed binding of the property name below),
     * comma-separated - e.g. {@code https://owleo-web.onrender.com}. */
    @Value("${nest.cors.allowed-origins:http://localhost:5000,http://localhost:*,http://127.0.0.1:*}")
    private String allowedOrigins;

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http, JwtAuthFilter jwtAuthFilter,
                                                     ActivityTrackingFilter activityTrackingFilter,
                                                     NestAuthenticationEntryPoint authenticationEntryPoint) throws Exception {
        http
                .csrf(AbstractHttpConfigurer::disable)
                .cors(cors -> cors.configurationSource(corsConfigurationSource()))
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(ex -> ex.authenticationEntryPoint(authenticationEntryPoint))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(PUBLIC_PATHS).permitAll()
                        .anyRequest().authenticated())
                .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class)
                // AFTER JwtAuthFilter on purpose - it reads the principal that filter sets in
                // TenantContext, which is cleared as soon as JwtAuthFilter's doFilter returns.
                .addFilterAfter(activityTrackingFilter, JwtAuthFilter.class);

        return http.build();
    }

    private CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        List<String> origins = Arrays.asList(allowedOrigins.split(","));
        configuration.setAllowedOriginPatterns(origins);
        configuration.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        configuration.setAllowedHeaders(List.of("Authorization", "Content-Type", "X-Active-Membership", "X-Internal-Api-Key"));
        configuration.setExposedHeaders(List.of("Authorization"));
        configuration.setAllowCredentials(true);
        configuration.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
