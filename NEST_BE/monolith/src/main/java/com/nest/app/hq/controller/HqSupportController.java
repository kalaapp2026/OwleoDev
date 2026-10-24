package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqSupport;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/admin/hq/support")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqSupportController {

    private final HqAccess access;
    private final HqSupport support;

    public HqSupportController(HqAccess access, HqSupport support) {
        this.access = access;
        this.support = support;
    }

    @GetMapping
    public Map<String, Object> list(@RequestParam(defaultValue = "all") String kind, @RequestParam(defaultValue = "open") String st,
                                    @RequestParam(required = false) String q) {
        access.requireModule("support");
        return support.list(kind, st, q);
    }

    @GetMapping("/{id}")
    public Map<String, Object> detail(@PathVariable UUID id) {
        access.requireModule("support");
        return support.detail(id);
    }

    // Replying is open to every role that can open Support, including Finance for fee tickets.
    @PostMapping("/{id}/reply")
    public void reply(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        access.requireModule("support");
        support.reply(id, body.get("message"), body.get("status"), body.get("priority"));
    }

    @PostMapping("/{id}/escalate")
    public void escalate(@PathVariable UUID id) {
        access.requireModule("support");
        support.escalate(id);
    }

    @PostMapping("/{id}/review")
    public void review(@PathVariable UUID id) {
        access.requireModule("support");
        support.review(id);
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, Object> body) {
        access.requireModule("support");
        return Map.of("id", support.create(body));
    }
}
