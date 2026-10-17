package com.nest.app.notification.service;

import java.util.List;
import java.util.UUID;

/**
 * Published by the dispatcher once the in-app rows are written; handled after the surrounding
 * transaction commits so a push or WhatsApp is never sent for something that then rolls back, and
 * a slow provider never holds the caller's request open.
 */
public record ExternalDeliveryRequested(
        String eventKey,
        boolean push,
        boolean whatsapp,
        String whatsappTemplateName,
        List<Recipient> recipients
) {
    public record Recipient(UUID userId, String title, String body, List<String> whatsappParameters) {
    }
}
