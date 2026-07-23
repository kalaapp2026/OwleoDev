package com.nest.identity.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * DEV-ONLY stand-in. Logs the OTP instead of sending it over WhatsApp/SMS. Never deploy this
 * bean as-is to a real environment - replace with a WhatsApp Business API / Twilio-backed
 * implementation before Phase 4/5 integrations ship (PRD Section 5).
 */
@Component
public class LoggingOtpSender implements OtpSender {

    private static final Logger log = LoggerFactory.getLogger(LoggingOtpSender.class);

    @Override
    public void send(String rawPhone, String code) {
        log.warn("[DEV-ONLY OTP SENDER] Would send OTP '{}' to phone ending in '{}' via WhatsApp/SMS in production",
                code, rawPhone.length() > 2 ? rawPhone.substring(rawPhone.length() - 2) : rawPhone);
    }
}
