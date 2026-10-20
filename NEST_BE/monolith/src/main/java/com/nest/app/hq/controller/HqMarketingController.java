package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqRole;
import com.nest.app.hq.service.HqMarketing;
import com.nest.common.exception.ForbiddenException;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/admin/hq/marketing")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqMarketingController {

    private final HqAccess access;
    private final HqMarketing marketing;

    public HqMarketingController(HqAccess access, HqMarketing marketing) {
        this.access = access;
        this.marketing = marketing;
    }

    // Finance and Super run marketing: the same roles that see the module.
    private void write() {
        access.requireModule("marketing");
        HqRole r = access.role();
        if (r != HqRole.SUPER && r != HqRole.FINANCE) throw new ForbiddenException("Only a Super admin or Finance admin can run campaigns");
    }

    @GetMapping
    public Map<String, Object> list(@RequestParam(defaultValue = "all") String channel) {
        access.requireModule("marketing");
        return marketing.list(channel);
    }

    @GetMapping("/estimate")
    public Map<String, Object> estimate(@RequestParam UUID academy, @RequestParam(defaultValue = "ALL") String audience, @RequestParam(required = false) List<String> interests) {
        access.requireModule("marketing");
        return marketing.estimate(academy, audience.toUpperCase(), interests == null ? List.of() : interests);
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, Object> body) {
        write();
        return Map.of("id", marketing.create(body));
    }

    @PostMapping("/{id}/{action}")
    public void status(@PathVariable UUID id, @PathVariable String action) {
        write();
        marketing.setStatus(id, action);
    }

    @PutMapping("/{id}/results")
    public void results(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        marketing.recordResults(id, body);
    }
}
