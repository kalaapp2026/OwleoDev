package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqUsers;
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

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/admin/hq/users")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqUsersController {

    private final HqAccess access;
    private final HqUsers users;

    public HqUsersController(HqAccess access, HqUsers users) {
        this.access = access;
        this.users = users;
    }

    @GetMapping
    public Map<String, Object> list(@RequestParam(required = false) String q, @RequestParam(required = false) UUID academy,
                                    @RequestParam(required = false) String course, @RequestParam(required = false) String batch,
                                    @RequestParam(required = false) UUID trainer, @RequestParam(required = false) String status,
                                    @RequestParam(defaultValue = "all") String flt, @RequestParam(defaultValue = "12") int limit,
                                    @RequestParam(defaultValue = "0") int offset) {
        access.requireModule("users");
        return users.list(q, academy, course, batch, trainer, status, flt, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0));
    }

    @GetMapping("/filters")
    public Map<String, Object> filters(@RequestParam(required = false) UUID academy) {
        access.requireModule("users");
        return users.filters(academy);
    }

    @GetMapping("/{id}")
    public Map<String, Object> detail(@PathVariable UUID id) {
        access.requireModule("users");
        return users.detail(id);
    }

    @PostMapping("/{id}/reveal")
    public Map<String, String> reveal(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        access.requireModule("users");
        return Map.of("value", users.reveal(id, body.getOrDefault("field", "")));
    }

    @GetMapping("/{id}/edit")
    public Map<String, Object> editable(@PathVariable UUID id) {
        access.requireModule("users");
        return users.editable(id);
    }

    @PutMapping("/{id}")
    public void update(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        access.requireModule("users");
        access.requireWrite();
        users.update(id, body);
    }

    @PostMapping("/{id}/status")
    public void status(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        access.requireModule("users");
        access.requireWrite();
        users.setActive(id, Boolean.TRUE.equals(body.get("active")), (String) body.get("reason"), (String) body.get("note"));
    }
}
