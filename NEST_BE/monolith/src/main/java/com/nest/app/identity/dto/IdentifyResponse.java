package com.nest.app.identity.dto;

/** maskedPhone is only populated for AuthMethod.OTP - lets the client show "code sent to
 * xxxxxxxx10" without ever exposing the full number for an account it hasn't authenticated yet. */
public record IdentifyResponse(AuthMethod authMethod, String username, String maskedPhone) {
}
