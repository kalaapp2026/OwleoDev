package com.nest.app.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Without this, springdoc has no security scheme to show, so Swagger UI never renders the
 * Authorize button at all - "Try it out" silently sends unauthenticated requests. This registers
 * a single global "bearerAuth" scheme so every endpoint's lock icon and the top-level Authorize
 * dialog work, and paste-once-use-everywhere applies the token to every subsequent call.
 */
@Configuration
public class OpenApiConfig {

    private static final String SCHEME_NAME = "bearerAuth";

    @Bean
    public OpenAPI nestOpenApi() {
        return new OpenAPI()
                .info(new Info().title("NEST API").description(
                        "Paste the accessToken from POST /auth/login (or /auth/otp/verify) into Authorize below - " +
                        "just the raw token, no \"Bearer \" prefix needed.").version("v1"))
                .addSecurityItem(new SecurityRequirement().addList(SCHEME_NAME))
                .components(new Components().addSecuritySchemes(SCHEME_NAME,
                        new SecurityScheme()
                                .name(SCHEME_NAME)
                                .type(SecurityScheme.Type.HTTP)
                                .scheme("bearer")
                                .bearerFormat("JWT")));
    }
}
