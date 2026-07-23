package com.nest.common.exception;

import org.springframework.http.HttpStatus;

/** Missing, expired, or invalid JWT. */
public class UnauthorizedException extends NestException {
    public UnauthorizedException(String message) {
        super(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", message);
    }
}
