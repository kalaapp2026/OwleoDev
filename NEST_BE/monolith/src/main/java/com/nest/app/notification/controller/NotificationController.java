package com.nest.app.notification.controller;

import com.nest.app.notification.dto.BroadcastRequest;
import com.nest.app.notification.dto.NotificationResponse;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.security.TenantContext;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Personal, not academy-scoped (like Calendar) - a notification belongs to the user regardless
 * of which membership is currently active, so there's no @RequiresFeature gate here. Every read
 * endpoint is scoped to one {@link NotificationModule} so the ERP bell and Social bell stay
 * completely separate feeds. */
@RestController
@Tag(name = "Notifications")
public class NotificationController {

    private final NotificationService notificationService;

    public NotificationController(NotificationService notificationService) {
        this.notificationService = notificationService;
    }

    @GetMapping("/notifications")
    public List<NotificationResponse> list(@RequestParam NotificationModule module) {
        return notificationService.listForUser(TenantContext.currentUserId(), module);
    }

    /** Powers the bell's unread badge without shipping the whole list each poll. */
    @GetMapping("/notifications/unread-count")
    public Map<String, Long> unreadCount(@RequestParam NotificationModule module) {
        return Map.of("count", notificationService.unreadCount(TenantContext.currentUserId(), module));
    }

    @PostMapping("/notifications/{id}/read")
    public ResponseEntity<Void> markRead(@PathVariable UUID id) {
        notificationService.markRead(id, TenantContext.currentUserId());
        return ResponseEntity.noContent().build();
    }

    /** Super Admin announcement console - fans one composed message out to the chosen audience. */
    @PostMapping("/admin/notifications/broadcast")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public Map<String, Integer> broadcast(@Valid @RequestBody BroadcastRequest request) {
        return Map.of("recipients", notificationService.broadcast(request));
    }
}
