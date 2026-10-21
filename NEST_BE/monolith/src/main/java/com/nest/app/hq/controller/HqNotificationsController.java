package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqNotifications;
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
import java.util.UUID;

/** Notification templates: the wording, channels and audience for each moment, linked to a module. */
@RestController
@RequestMapping("/admin/hq/notifications")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqNotificationsController {

    private final HqAccess access;
    private final HqNotifications notifications;

    public HqNotificationsController(HqAccess access, HqNotifications notifications) {
        this.access = access;
        this.notifications = notifications;
    }

    @GetMapping
    public Map<String, Object> overview() {
        access.requireModule("notifs");
        return notifications.overview();
    }

    @GetMapping("/log")
    public List<Map<String, Object>> log(@RequestParam(required = false) String status) {
        access.requireModule("notifs");
        return notifications.log(status);
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, Object> body) {
        access.requireModule("notifs");
        access.requireWrite();
        return notifications.save(null, body);
    }

    @PutMapping("/{id}")
    public Map<String, Object> update(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        access.requireModule("notifs");
        access.requireWrite();
        return notifications.save(id, body);
    }

    @DeleteMapping("/{id}")
    public void delete(@PathVariable UUID id) {
        access.requireModule("notifs");
        access.requireWrite();
        notifications.delete(id);
    }

    /** Sends the message in the editor to the signed-in person only. */
    @PostMapping("/test")
    public List<Map<String, Object>> test(@RequestBody Map<String, Object> body) {
        access.requireModule("notifs");
        access.requireWrite();
        return notifications.test(body);
    }
}
