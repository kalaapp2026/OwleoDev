package com.nest.app.identity.service;

import com.nest.app.identity.entity.OtpPurpose;

/**
 * Dispatches an OTP code by email - the password-reset counterpart to {@link OtpSender}, which
 * handles the phone-delivered purposes. Kept as its own interface (rather than widening
 * {@link OtpSender}) since the two channels have nothing in common beyond "sends a code somewhere."
 */
public interface EmailSender {
    void sendOtp(String rawEmail, String code, OtpPurpose purpose);
}
