package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqExits;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/admin/hq/exits")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqExitsController {

    private final HqAccess access;
    private final HqExits exits;

    public HqExitsController(HqAccess access, HqExits exits) {
        this.access = access;
        this.exits = exits;
    }

    @GetMapping
    public Map<String, Object> list() {
        access.requireModule("exits");
        return exits.list();
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, String> body) {
        access.requireModule("exits");
        access.requireWrite();
        String academy = body.get("academyId");
        return Map.of("id", exits.create(UUID.fromString(body.getOrDefault("userId", "")), academy == null || academy.isBlank() ? null : UUID.fromString(academy),
                body.get("reason"), body.get("effective")));
    }

    @PostMapping("/{id}/clearance")
    public void clearance(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        access.requireModule("exits");
        access.requireWrite();
        exits.clearance(id, ((Number) body.get("index")).intValue(), Boolean.TRUE.equals(body.get("done")));
    }

    @PostMapping("/{id}/complete")
    public void complete(@PathVariable UUID id) {
        access.requireModule("exits");
        access.requireWrite();
        exits.complete(id);
    }
}
