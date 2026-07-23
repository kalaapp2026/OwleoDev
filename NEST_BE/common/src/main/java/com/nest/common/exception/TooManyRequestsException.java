package com.nest.common.exception;

import org.springframework.http.HttpStatus;

/** OTP request throttling (PRD 4.6: "rate-limiting applied specifically to pending-membership-
 * confirmation requests per admin... to prevent a careless or malicious admin from poking random
 * phone numbers"), also reused for general OTP-request throttling per phone number. */
public class TooManyRequestsException extends NestException {
    public TooManyRequestsException(String message) {
        super(HttpStatus.TOO_MANY_REQUESTS, "TOO_MANY_REQUESTS", message);
    }
}
