package com.nest.app.platform.controller;

import com.nest.app.platform.dto.PlatformOverviewResponse;
import com.nest.app.platform.service.PlatformMetricsService;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Super Admin console's cross-tenant analytics. SUPER_ADMIN only - these are the one set of
 * endpoints in the app that deliberately read across every academy at once.
 */
@RestController
@Tag(name = "Platform (Super Admin)")
public class PlatformMetricsController {

    private final PlatformMetricsService platformMetricsService;

    public PlatformMetricsController(PlatformMetricsService platformMetricsService) {
        this.platformMetricsService = platformMetricsService;
    }

    @GetMapping("/admin/platform/overview")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public PlatformOverviewResponse overview() {
        return platformMetricsService.overview();
    }
}
