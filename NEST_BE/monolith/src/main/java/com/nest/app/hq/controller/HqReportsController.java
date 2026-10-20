package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqReports;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/admin/hq/reports")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqReportsController {

    private final HqAccess access;
    private final HqReports reports;

    public HqReportsController(HqAccess access, HqReports reports) {
        this.access = access;
        this.reports = reports;
    }

    @GetMapping
    public Map<String, Object> summary(@RequestParam(required = false) UUID academy, @RequestParam(defaultValue = "12") int months) {
        access.requireModule("reports");
        return reports.summary(academy, clamp(months));
    }

    /** One report's rows, for the console to turn into a CSV. Authorised roles only, and every call is audited. */
    @GetMapping("/{key}")
    public Map<String, Object> data(@PathVariable String key, @RequestParam(required = false) UUID academy, @RequestParam(defaultValue = "12") int months) {
        access.requireModule("reports");
        access.requireExport();
        return reports.data(key, academy, clamp(months), true);
    }

    private static int clamp(int m) {
        return m == 1 || m == 3 ? m : 12;
    }
}
