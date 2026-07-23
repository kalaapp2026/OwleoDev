package com.nest.academy.client;

import com.nest.academy.config.IdentityServiceProperties;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.UpstreamServiceException;
import com.nest.common.security.InternalApiKeyProperties;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

/**
 * Synchronous internal call to identity-service's /internal/academy-admins endpoint (PRD 3.2
 * onboarding). Uses {@link RestClient} (Spring 6.1+, ships with spring-boot-starter-web) rather
 * than WebClient specifically so this stays a plain servlet-stack service - pulling in
 * spring-boot-starter-webflux here would start a second reactive server alongside Tomcat.
 *
 * <p>This is a synchronous call for Phase 1 simplicity. A saga/event-driven handoff
 * (academy.created -> identity-service reacts via Kafka) would be more resilient to
 * identity-service being briefly unavailable and is worth revisiting once Kafka is wired (Phase 4+).
 */
@Component
public class IdentityServiceClient {

    private final RestClient restClient;
    private final InternalApiKeyProperties apiKeyProperties;

    public IdentityServiceClient(IdentityServiceProperties properties, InternalApiKeyProperties apiKeyProperties) {
        this.restClient = RestClient.builder().baseUrl(properties.getBaseUrl()).build();
        this.apiKeyProperties = apiKeyProperties;
    }

    public IdentityAdminProvisionResponse provisionAcademyAdmin(IdentityAdminProvisionRequest request) {
        try {
            return restClient.post()
                    .uri("/internal/academy-admins")
                    .header(apiKeyProperties.getHeaderName(), apiKeyProperties.getKey())
                    .body(request)
                    .retrieve()
                    .body(IdentityAdminProvisionResponse.class);
        } catch (RestClientResponseException ex) {
            if (ex.getStatusCode() == HttpStatusCode.valueOf(409)) {
                throw new ConflictException("identity-service rejected admin provisioning: " + ex.getResponseBodyAsString());
            }
            throw new UpstreamServiceException("identity-service call failed (" + ex.getStatusCode() + "): " + ex.getResponseBodyAsString());
        } catch (Exception ex) {
            throw new UpstreamServiceException("identity-service is unreachable: " + ex.getMessage());
        }
    }
}
