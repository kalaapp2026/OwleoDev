package com.nest.identity.service;

/**
 * Dispatches the OTP code to the user. Phase 1 only ships {@link LoggingOtpSender} - real
 * WhatsApp Business API / SMS gateway wiring is external-integration work slated for later phases
 * (PRD Section 5). Swap the Spring bean, not the call sites, when that lands.
 */
public interface OtpSender {
    void send(String rawPhone, String code);
}
