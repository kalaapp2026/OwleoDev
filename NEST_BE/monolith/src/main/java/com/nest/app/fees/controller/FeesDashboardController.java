package com.nest.app.fees.controller;

import com.nest.app.fees.dto.FeeSummaryResponse;
import com.nest.app.fees.dto.StudentSearchResult;
import com.nest.app.fees.service.FeesDashboardService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/** The fees landing: category totals and a search across every student. */
@RestController
@Tag(name = "Fees")
public class FeesDashboardController {

    private final FeesDashboardService dashboardService;

    public FeesDashboardController(FeesDashboardService dashboardService) {
        this.dashboardService = dashboardService;
    }

    @GetMapping("/fees/summary")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public FeeSummaryResponse summary(@RequestParam String period,
                                      @RequestParam(required = false) UUID courseId,
                                      @RequestParam(required = false) UUID batchId) {
        return dashboardService.summary(period, courseId, batchId);
    }

    @GetMapping("/fees/students/search")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public List<StudentSearchResult> searchStudents(@RequestParam String query,
                                                    @RequestParam(defaultValue = "12") int limit) {
        return dashboardService.searchStudents(query, limit);
    }
}
