package com.nest.common.exception;

import org.springframework.http.HttpStatus;

public class BadRequestException extends NestException {
    public BadRequestException(String message) {
        super(HttpStatus.BAD_REQUEST, "BAD_REQUEST", message);
    }
}
