package com.nest.app.platform.controller;

import com.nest.app.platform.dto.AcademyStatsResponse;
import com.nest.app.platform.dto.PlatformOverviewResponse;
import com.nest.app.platform.service.AcademyStatsService;
import com.nest.app.platform.service.PlatformMetricsService;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * The Super Admin console's cross-tenant analytics. SUPER_ADMIN only - these are the one set of
 * endpoints in the app that deliberately read across every academy at once.
 */
@RestController
@Tag(name = "Platform (Super Admin)")
public class PlatformMetricsController {

    private final PlatformMetricsService platformMetricsService;
    private final AcademyStatsService academyStatsService;

    public PlatformMetricsController(PlatformMetricsService platformMetricsService,
                                     AcademyStatsService academyStatsService) {
        this.platformMetricsService = platformMetricsService;
        this.academyStatsService = academyStatsService;
    }

    @GetMapping("/admin/platform/overview")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public PlatformOverviewResponse overview() {
        return platformMetricsService.overview();
    }

    /** Every academy with its headline counts - the console's tenant table. */
    @GetMapping("/admin/platform/academies")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public List<AcademyStatsResponse> academies() {
        return academyStatsService.listAll();
    }

    @GetMapping("/admin/platform/academies/{academyId}")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public AcademyStatsResponse academy(@PathVariable UUID academyId) {
        return academyStatsService.detail(academyId);
    }
}
