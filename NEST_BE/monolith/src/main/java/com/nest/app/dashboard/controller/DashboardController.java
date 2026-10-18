package com.nest.app.dashboard.controller;

import com.nest.app.dashboard.dto.DashboardStatsResponse;
import com.nest.app.dashboard.service.DashboardService;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The ERP home screen's stats row. Not {@code @RequiresFeature}-gated, like Calendar and
 * Notifications - every member with an active membership may ask. Without {@code scope=mine} it is
 * the academy-wide headcount (the About page); with it, only the courses the caller holds a
 * feature on, which is what the Dashboard shows a trainer. */
@RestController
@Tag(name = "Dashboard")
public class DashboardController {

    private final DashboardService dashboardService;

    public DashboardController(DashboardService dashboardService) {
        this.dashboardService = dashboardService;
    }

    @GetMapping("/dashboard/stats")
    public DashboardStatsResponse stats(@RequestParam(required = false) String scope) {
        return dashboardService.stats("mine".equalsIgnoreCase(scope));
    }
}
