package com.nest.common.exception;

import org.springframework.http.HttpStatus;

public class ResourceNotFoundException extends NestException {
    public ResourceNotFoundException(String message) {
        super(HttpStatus.NOT_FOUND, "RESOURCE_NOT_FOUND", message);
    }
}
