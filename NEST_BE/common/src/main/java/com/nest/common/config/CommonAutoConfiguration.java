package com.nest.common.config;

import com.nest.common.audit.AuditAspect;
import com.nest.common.audit.Slf4jAuditPublisher;
import com.nest.common.crypto.CryptoProperties;
import com.nest.common.crypto.PiiEncryptor;
import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.GlobalExceptionHandler;
import com.nest.common.security.FeatureAuthorizationAspect;
import com.nest.common.security.InternalApiKeyFilter;
import com.nest.common.security.InternalApiKeyProperties;
import com.nest.common.security.JwtAuthFilter;
import com.nest.common.security.JwtProperties;
import com.nest.common.security.JwtTokenProvider;
import com.nest.common.security.NestAuthenticationEntryPoint;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Import;

/**
 * Every NEST service picks this up automatically (Spring Boot 3 auto-configuration import file)
 * the moment it depends on {@code common} - no manual wiring needed beyond plugging
 * {@link JwtAuthFilter} into the service's own {@code SecurityFilterChain}, since permitAll
 * paths are necessarily service-specific.
 */
@AutoConfiguration
@EnableConfigurationProperties({JwtProperties.class, CryptoProperties.class, InternalApiKeyProperties.class})
@Import({
        JwtTokenProvider.class,
        JwtAuthFilter.class,
        FeatureAuthorizationAspect.class,
        AuditAspect.class,
        Slf4jAuditPublisher.class,
        GlobalExceptionHandler.class,
        PiiEncryptor.class,
        PiiHasher.class,
        InternalApiKeyFilter.class,
        NestAuthenticationEntryPoint.class
})
public class CommonAutoConfiguration {
}
