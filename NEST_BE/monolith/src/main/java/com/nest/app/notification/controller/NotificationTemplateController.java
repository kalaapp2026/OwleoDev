package com.nest.app.notification.controller;

import com.nest.app.notification.dto.NotificationTemplateDtos.CatalogResponse;
import com.nest.app.notification.dto.NotificationTemplateDtos.DeliveryView;
import com.nest.app.notification.dto.NotificationTemplateDtos.RegisterTokenRequest;
import com.nest.app.notification.dto.NotificationTemplateDtos.SaveRequest;
import com.nest.app.notification.dto.NotificationTemplateDtos.TemplateView;
import com.nest.app.notification.service.NotificationTemplateService;
import com.nest.app.notification.service.PushTokenService;
import com.nest.common.security.TenantContext;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** Super Admin console for notification templates, plus the device-token registration the mobile
 * app calls so push has somewhere to go. */
@RestController
@Tag(name = "Notification templates (Super Admin)")
public class NotificationTemplateController {

    private final NotificationTemplateService templateService;
    private final PushTokenService pushTokenService;

    public NotificationTemplateController(NotificationTemplateService templateService, PushTokenService pushTokenService) {
        this.templateService = templateService;
        this.pushTokenService = pushTokenService;
    }

    @GetMapping("/admin/notification-templates")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public CatalogResponse catalog() {
        return templateService.catalog();
    }

    @PutMapping("/admin/notification-templates/{eventKey}")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public TemplateView save(@PathVariable String eventKey, @Valid @RequestBody SaveRequest request) {
        return templateService.save(eventKey, request, TenantContext.currentUserId());
    }

    @DeleteMapping("/admin/notification-templates/{eventKey}")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public ResponseEntity<Void> delete(@PathVariable String eventKey) {
        templateService.delete(eventKey);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/admin/notification-templates/{eventKey}/test")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public ResponseEntity<Void> test(@PathVariable String eventKey) {
        templateService.sendTest(eventKey, TenantContext.currentUserId());
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/admin/notification-deliveries")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public List<DeliveryView> deliveries(@RequestParam(defaultValue = "50") int limit) {
        return templateService.recentDeliveries(limit);
    }

    /** Any signed-in user: called by the mobile app after login (and whenever FCM rotates the token). */
    @PostMapping("/notifications/push-token")
    public ResponseEntity<Void> registerToken(@Valid @RequestBody RegisterTokenRequest request) {
        pushTokenService.register(TenantContext.currentUserId(), request.token(), request.platform());
        return ResponseEntity.noContent().build();
    }

    /** Called on sign-out so a shared phone stops receiving the previous person's alerts. */
    @DeleteMapping("/notifications/push-token")
    public ResponseEntity<Void> unregisterToken(@RequestParam String token) {
        pushTokenService.unregister(TenantContext.currentUserId(), token);
        return ResponseEntity.noContent().build();
    }
}
