package com.nest.app.notification.controller;

import com.nest.app.notification.dto.NotificationResponse;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.security.TenantContext;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/** Personal, not academy-scoped (like Calendar) - a notification belongs to the user regardless
 * of which membership is currently active, so there's no @RequiresFeature gate here. */
@RestController
@Tag(name = "Notifications")
public class NotificationController {

    private final NotificationService notificationService;

    public NotificationController(NotificationService notificationService) {
        this.notificationService = notificationService;
    }

    @GetMapping("/notifications")
    public List<NotificationResponse> list() {
        return notificationService.listForUser(TenantContext.currentUserId());
    }

    @PostMapping("/notifications/{id}/read")
    public ResponseEntity<Void> markRead(@PathVariable UUID id) {
        notificationService.markRead(id, TenantContext.currentUserId());
        return ResponseEntity.noContent().build();
    }
}
