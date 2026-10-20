package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqRole;
import com.nest.app.hq.service.HqAcademies;
import com.nest.app.hq.service.HqAcademyService;
import com.nest.app.hq.service.HqImport;
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

/** HQ's Entities module: every academy, and what HQ can do to one. */
@RestController
@RequestMapping("/admin/hq/academies")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqAcademyController {

    private final HqAccess access;
    private final HqAcademies academies;
    private final HqAcademyService service;
    private final HqImport importer;

    public HqAcademyController(HqAccess access, HqAcademies academies, HqAcademyService service, HqImport importer) {
        this.access = access;
        this.academies = academies;
        this.service = service;
        this.importer = importer;
    }

    /** Checks (commit=false) or imports (commit=true) students from CSV rows. Credentials are returned once. */
    @PostMapping("/{id}/import")
    @SuppressWarnings("unchecked")
    public Map<String, Object> importStudents(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        access.requireModule("academies");
        access.requireWrite();
        return importer.run(id, (java.util.List<Map<String, Object>>) body.get("rows"), Boolean.TRUE.equals(body.get("commit")));
    }

    @GetMapping
    public List<HqAcademies.Row> list() {
        access.requireModule("academies");
        return academies.all();
    }

    @GetMapping("/{id}")
    public Map<String, Object> detail(@PathVariable UUID id) {
        access.requireModule("academies");
        return service.detail(id);
    }

    @PutMapping("/{id}")
    public void edit(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        access.requireModule("academies");
        access.requireWrite();
        service.edit(id, body);
    }

    @PostMapping("/{id}/suspend")
    public void suspend(@PathVariable UUID id) {
        access.requireModule("academies");
        access.requireWrite();
        service.setSuspended(id, true);
    }

    @PostMapping("/{id}/reactivate")
    public void reactivate(@PathVariable UUID id) {
        access.requireModule("academies");
        access.requireWrite();
        service.setSuspended(id, false);
    }

    /** Plans are Finance's and Super's call, not Operations'. */
    @PutMapping("/{id}/plan")
    public void changePlan(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        HqRole role = access.role();
        if (role != HqRole.SUPER && role != HqRole.FINANCE) {
            throw new ForbiddenException("Only a Super admin or Finance admin can change a plan");
        }
        service.changePlan(id, body.get("planCode"), body.get("reason"));
    }

    @GetMapping("/{id}/people")
    public List<Map<String, Object>> people(@PathVariable UUID id, @RequestParam String kind,
                                            @RequestParam(required = false) String q) {
        access.requireModule("academies");
        return service.people(id, kind, q);
    }

    @PutMapping("/{id}/banks/{bankId}/gateway")
    public void mapGateway(@PathVariable UUID id, @PathVariable UUID bankId, @RequestBody Map<String, String> body) {
        HqRole role = access.role();
        if (role != HqRole.SUPER && role != HqRole.OPS && role != HqRole.FINANCE) {
            throw new ForbiddenException("This role cannot map payment gateways");
        }
        service.mapGateway(id, bankId, body.get("provider"), body.get("merchantId"));
    }
}
