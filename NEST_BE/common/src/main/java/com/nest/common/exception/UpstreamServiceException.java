package com.nest.common.exception;

import org.springframework.http.HttpStatus;

/** A call to another NEST service (or third-party integration) failed unexpectedly. */
public class UpstreamServiceException extends NestException {
    public UpstreamServiceException(String message) {
        super(HttpStatus.BAD_GATEWAY, "UPSTREAM_SERVICE_ERROR", message);
    }
}
