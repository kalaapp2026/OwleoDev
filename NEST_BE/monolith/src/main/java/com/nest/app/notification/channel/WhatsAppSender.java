package com.nest.app.notification.channel;

import java.util.List;

/** Delivers a pre-approved WhatsApp template message to one phone number. */
public interface WhatsAppSender {
    boolean isConfigured();

    ChannelResult sendTemplate(String rawPhone, String templateName, List<String> bodyParameters);
}
