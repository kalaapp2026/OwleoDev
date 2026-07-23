package com.nest.common.exception;

import org.springframework.http.HttpStatus;

/** e.g. duplicate username, academy name+city collision, double-booking a Regular batch slot. */
public class ConflictException extends NestException {
    public ConflictException(String message) {
        super(HttpStatus.CONFLICT, "CONFLICT", message);
    }
}
