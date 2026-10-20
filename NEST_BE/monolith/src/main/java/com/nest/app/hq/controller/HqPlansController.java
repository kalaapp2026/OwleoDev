package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqRole;
import com.nest.app.hq.service.HqPlansService;
import com.nest.common.exception.ForbiddenException;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
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

@RestController
@RequestMapping("/admin/hq/plans")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqPlansController {

    private final HqAccess access;
    private final HqPlansService service;

    public HqPlansController(HqAccess access, HqPlansService service) {
        this.access = access;
        this.service = service;
    }

    /** Readable by anyone who can open Plans, Academies or Collections: they all need to pick a plan. */
    @GetMapping
    public List<Map<String, Object>> list() {
        HqRole role = access.role();
        if (!role.canOpen("plans") && !role.canOpen("academies") && !role.canOpen("collections")) {
            throw new ForbiddenException(role.label() + " cannot open plans");
        }
        return service.list();
    }

    @PostMapping
    public void create(@RequestBody Map<String, Object> body) {
        writer();
        service.save(null, body);
    }

    @PutMapping("/{code}")
    public void update(@PathVariable String code, @RequestBody Map<String, Object> body) {
        writer();
        service.save(code, body);
    }

    @DeleteMapping("/{code}")
    public void delete(@PathVariable String code, @RequestParam(required = false) String moveTo) {
        writer();
        service.delete(code, moveTo);
    }

    private void writer() {
        HqRole role = access.role();
        if (role != HqRole.SUPER && role != HqRole.FINANCE) {
            throw new ForbiddenException("Only a Super admin or Finance admin can change plans");
        }
    }
}
