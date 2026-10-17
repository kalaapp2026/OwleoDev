package com.nest.app.notification.channel;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * WhatsApp Business Cloud API (Meta). Business-initiated messages must use a template approved in
 * Meta Business Manager, so the Super Admin enters that template's name and we fill its numbered
 * variables - see {@code NotificationDispatcher} for the ordering rule.
 *
 * <p>Not configured (no token / phone-number id) = every send is SKIPPED.</p>
 */
@Component
public class MetaWhatsAppSender implements WhatsAppSender {

    private static final Logger log = LoggerFactory.getLogger(MetaWhatsAppSender.class);

    private final RestClient http = RestClient.create();
    private final String accessToken;
    private final String phoneNumberId;
    private final String apiVersion;
    private final String defaultCountryCode;
    private final String languageCode;

    public MetaWhatsAppSender(
            @Value("${nest.whatsapp.access-token:}") String accessToken,
            @Value("${nest.whatsapp.phone-number-id:}") String phoneNumberId,
            @Value("${nest.whatsapp.api-version:v20.0}") String apiVersion,
            @Value("${nest.whatsapp.default-country-code:91}") String defaultCountryCode,
            @Value("${nest.whatsapp.language:en}") String languageCode) {
        this.accessToken = accessToken;
        this.phoneNumberId = phoneNumberId;
        this.apiVersion = apiVersion;
        this.defaultCountryCode = defaultCountryCode;
        this.languageCode = languageCode;
    }

    @Override
    public boolean isConfigured() {
        return !accessToken.isBlank() && !phoneNumberId.isBlank();
    }

    @Override
    public ChannelResult sendTemplate(String rawPhone, String templateName, List<String> bodyParameters) {
        if (!isConfigured()) return ChannelResult.skipped("WhatsApp is not configured (nest.whatsapp.*)");
        if (templateName == null || templateName.isBlank()) return ChannelResult.skipped("No WhatsApp template name set");
        String to = normalise(rawPhone);
        if (to == null) return ChannelResult.skipped("No usable phone number");

        List<Map<String, String>> parameters = new ArrayList<>();
        for (String value : bodyParameters) {
            // Meta rejects empty parameters, so a blank value becomes a dash.
            parameters.add(Map.of("type", "text", "text", value == null || value.isBlank() ? "-" : value));
        }
        Map<String, Object> template = new LinkedHashMap<>();
        template.put("name", templateName);
        template.put("language", Map.of("code", languageCode));
        if (!parameters.isEmpty()) template.put("components", List.of(Map.of("type", "body", "parameters", parameters)));

        try {
            http.post()
                    .uri("https://graph.facebook.com/" + apiVersion + "/" + phoneNumberId + "/messages")
                    .header("Authorization", "Bearer " + accessToken)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("messaging_product", "whatsapp", "to", to, "type", "template", "template", template))
                    .retrieve()
                    .toBodilessEntity();
            return ChannelResult.sent();
        } catch (RestClientResponseException e) {
            log.warn("WhatsApp send failed: {} {}", e.getStatusCode(), e.getResponseBodyAsString());
            return ChannelResult.failed("WhatsApp " + e.getStatusCode().value() + ": " + e.getResponseBodyAsString());
        } catch (Exception e) {
            log.warn("WhatsApp send failed", e);
            return ChannelResult.failed(e.getClass().getSimpleName() + ": " + e.getMessage());
        }
    }

    /** Digits only, country code included, no '+'. A bare 10-digit number gets the default code. */
    String normalise(String rawPhone) {
        if (rawPhone == null) return null;
        String digits = rawPhone.replaceAll("\\D", "");
        if (digits.isEmpty()) return null;
        if (digits.length() == 10) return defaultCountryCode + digits;
        return digits.length() >= 11 ? digits : null;
    }
}
