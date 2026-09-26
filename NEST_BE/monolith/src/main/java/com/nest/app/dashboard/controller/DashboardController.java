package com.nest.app.dashboard.controller;

import com.nest.app.dashboard.dto.DashboardStatsResponse;
import com.nest.app.dashboard.service.DashboardService;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** The ERP home screen's stats row. Not {@code @RequiresFeature}-gated, like Calendar and
 * Notifications - it's a headcount for whichever academy is currently active, not a roster, so
 * every member with an active membership may see it. */
@RestController
@Tag(name = "Dashboard")
public class DashboardController {

    private final DashboardService dashboardService;

    public DashboardController(DashboardService dashboardService) {
        this.dashboardService = dashboardService;
    }

    @GetMapping("/dashboard/stats")
    public DashboardStatsResponse stats() {
        return dashboardService.stats();
    }
}
