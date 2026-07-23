package com.nest.common.exception;

import org.springframework.http.HttpStatus;

/**
 * Base of the exception hierarchy every service should throw for expected, mapped failures.
 * {@link com.nest.common.exception.GlobalExceptionHandler} converts these into a consistent
 * {@link com.nest.common.dto.ErrorResponse} shape.
 */
public class NestException extends RuntimeException {

    private final HttpStatus status;
    private final String code;

    public NestException(HttpStatus status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public HttpStatus getStatus() {
        return status;
    }

    public String getCode() {
        return code;
    }
}
