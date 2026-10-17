package com.nest.app.notification.dto;

import com.nest.app.notification.entity.DeliveryStatus;
import com.nest.app.notification.entity.NotificationChannel;
import com.nest.app.notification.entity.NotificationModule;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class NotificationTemplateDtos {

    private NotificationTemplateDtos() {
    }

    /** Whether each channel can actually deliver right now (credentials present). In-app always can. */
    public record ChannelStatus(boolean inApp, boolean push, boolean whatsapp) {
    }

    /** The saved wording and channel switches; null on an event until a Super Admin configures it. */
    public record TemplateView(
            String title,
            String body,
            boolean inAppEnabled,
            boolean pushEnabled,
            boolean whatsappEnabled,
            String whatsappTemplateName,
            boolean enabled,
            Instant updatedAt
    ) {
    }

    /** One catalogued event, with its template if configured and the starter wording to prefill. */
    public record EventView(
            String eventKey,
            NotificationModule module,
            String label,
            String description,
            List<String> placeholders,
            String defaultTitle,
            String defaultBody,
            TemplateView template
    ) {
    }

    public record CatalogResponse(ChannelStatus channels, List<EventView> events) {
    }

    public record SaveRequest(
            @NotBlank @Size(max = 200) String title,
            @NotBlank @Size(max = 1000) String body,
            boolean inAppEnabled,
            boolean pushEnabled,
            boolean whatsappEnabled,
            @Size(max = 120) String whatsappTemplateName,
            boolean enabled
    ) {
    }

    public record DeliveryView(
            UUID id,
            String recipientName,
            String eventKey,
            NotificationChannel channel,
            DeliveryStatus status,
            String detail,
            Instant createdAt
    ) {
    }

    public record RegisterTokenRequest(@NotBlank @Size(max = 512) String token, @Size(max = 20) String platform) {
    }
}
