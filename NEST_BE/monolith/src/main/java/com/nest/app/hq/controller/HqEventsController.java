package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqEvents;
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
@RequestMapping("/admin/hq/events")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqEventsController {

    private final HqAccess access;
    private final HqEvents events;

    public HqEventsController(HqAccess access, HqEvents events) {
        this.access = access;
        this.events = events;
    }

    @GetMapping
    public Map<String, Object> list(@RequestParam(defaultValue = "upcoming") String when, @RequestParam(required = false) String day,
                                    @RequestParam(required = false) String q) {
        access.requireModule("events");
        return events.list(when, day, q);
    }

    @GetMapping("/{id}")
    public Map<String, Object> detail(@PathVariable UUID id) {
        access.requireModule("events");
        return events.detail(id);
    }

    @PostMapping("/{id}/pause")
    public void pause(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        access.requireModule("events");
        access.requireWrite();
        events.pause(id, body.get("reason"));
    }

    @PostMapping("/{id}/resume")
    public void resume(@PathVariable UUID id) {
        access.requireModule("events");
        access.requireWrite();
        events.resume(id);
    }

    @PostMapping("/{id}/cancel")
    public void cancel(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        access.requireModule("events");
        access.requireWrite();
        events.cancel(id, body.get("reason"));
    }
}
