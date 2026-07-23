package com.nest.common.exception;

import org.springframework.http.HttpStatus;

/** Caller is authenticated but the role/feature/course-map intersection denies this action (PRD 2.3). */
public class ForbiddenException extends NestException {
    public ForbiddenException(String message) {
        super(HttpStatus.FORBIDDEN, "FORBIDDEN", message);
    }
}
