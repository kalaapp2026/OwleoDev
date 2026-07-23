package com.nest.identity.controller;

import com.nest.identity.dto.ProvisionAcademyAdminRequest;
import com.nest.identity.dto.ProvisionAcademyAdminResponse;
import com.nest.identity.service.InternalProvisioningService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * Service-to-service only, gated by {@link com.nest.common.security.InternalApiKeyFilter} - never
 * exposed through the public gateway route table.
 */
@RestController
@Tag(name = "Internal", description = "Service-to-service endpoints, not for the Flutter client")
public class InternalController {

    private final InternalProvisioningService provisioningService;

    public InternalController(InternalProvisioningService provisioningService) {
        this.provisioningService = provisioningService;
    }

    @PostMapping("/internal/academy-admins")
    public ProvisionAcademyAdminResponse provisionAcademyAdmin(@Valid @RequestBody ProvisionAcademyAdminRequest request) {
        return provisioningService.provisionAcademyAdmin(request);
    }
}
